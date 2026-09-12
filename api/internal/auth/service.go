package auth

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"connectrpc.com/connect"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/crypto/bcrypt"
	"google.golang.org/protobuf/types/known/timestamppb"

	"example/app/gen/db"
	authv1 "example/app/gen/go/auth/v1"
	"example/app/internal/rpcerr"
)

const (
	// maxEmailLen is the longest address that can be delivered to, counted the
	// way the proto rule and the table's check count it.
	maxEmailLen = 254
	// minPasswordLen is the shortest password accepted, in bytes.
	minPasswordLen = 8
	// maxPasswordLen is bcrypt's own limit: it reads no further, so a longer
	// password would be weaker than the client believes it to be.
	maxPasswordLen = 72
)

// uniqueViolation is the SQLSTATE Postgres raises for a duplicate key.
const uniqueViolation = "23505"

// dummyHash is what a login for an unknown address is compared against, so
// that answer costs the same as a wrong password and the time it takes does
// not say which addresses have an account. Computed on first use because
// bcrypt is deliberately slow.
var dummyHash = sync.OnceValue(func() []byte {
	hash, err := bcrypt.GenerateFromPassword([]byte("this password belongs to nobody"), bcrypt.DefaultCost)
	if err != nil {
		panic(err)
	}

	return hash
})

type Querier interface {
	CreateUser(ctx context.Context, arg db.CreateUserParams) (db.User, error)
	GetUserByEmail(ctx context.Context, email string) (db.User, error)
	CreateSession(ctx context.Context, arg db.CreateSessionParams) (db.Session, error)
	DeleteSession(ctx context.Context, arg db.DeleteSessionParams) error
}

type Service struct {
	queries Querier
	issuer  *Issuer
	// secureCookies withholds the session cookie from plain http (cookie.go).
	secureCookies bool
}

func NewService(queries Querier, issuer *Issuer, secureCookies bool) *Service {
	return &Service{queries: queries, issuer: issuer, secureCookies: secureCookies}
}

// invalidCredentials is the single answer to every failed login, so the API
// does not say whether an address has an account.
func invalidCredentials() *connect.Error {
	return connect.NewError(
		connect.CodeUnauthenticated,
		errors.New("email or password is incorrect"),
	)
}

// validEmail lower-cases the address, so that addresses differing only in
// case are one account, and rejects what could not be one. The proto field
// declares a stricter rule, enforced by the server's validate interceptor
// (proto/auth/v1/auth.proto); what is here keeps the service safe when it is
// called without one.
//
// The trim serves only that second purpose. An address padded with space is
// not one the proto rule accepts, so none arrives here through the API; taking
// the space off is what would stop two spellings of one address from reaching
// the unique constraint as two, were the service ever called unguarded.
func validEmail(raw string) (string, error) {
	email := strings.ToLower(strings.TrimSpace(raw))
	if email == "" || utf8.RuneCountInString(email) > maxEmailLen || !strings.Contains(email, "@") {
		return "", connect.NewError(
			connect.CodeInvalidArgument,
			fmt.Errorf("email must be an address of at most %d characters", maxEmailLen),
		)
	}

	return email, nil
}

// validPassword bounds the password the same way the proto field does, in
// bytes, because that is the unit bcrypt's limit is expressed in.
func validPassword(password string) error {
	if len(password) < minPasswordLen || len(password) > maxPasswordLen {
		return connect.NewError(
			connect.CodeInvalidArgument,
			fmt.Errorf("password must be between %d and %d bytes", minPasswordLen, maxPasswordLen),
		)
	}

	return nil
}

// issueToken opens a session for the account, signs a token naming it, puts
// that token on the response as the session cookie, and returns it for the
// clients that carry it themselves.
//
// The row comes first because the token has to name it. A row whose token was
// never signed authenticates nothing and is swept with the account's other
// finished sessions (api/queries/sessions.sql).
func (s *Service) issueToken(
	ctx context.Context,
	userID int64,
	header http.Header,
) (*authv1.Token, error) {
	now := time.Now()
	expiresAt := s.issuer.Expiry(now)

	session, err := s.queries.CreateSession(ctx, db.CreateSessionParams{
		UserID:    userID,
		ExpiresAt: pgtype.Timestamptz{Time: expiresAt, Valid: true},
	})
	if err != nil {
		return nil, rpcerr.Internal(ctx, "opening session", err)
	}

	accessToken, err := s.issuer.Issue(userID, session.ID, now, expiresAt)
	if err != nil {
		return nil, rpcerr.Internal(ctx, "issuing token", err)
	}

	header.Add("Set-Cookie", sessionCookie(accessToken, expiresAt, s.secureCookies).String())

	return &authv1.Token{
		AccessToken: accessToken,
		ExpiresAt:   timestamppb.New(expiresAt),
	}, nil
}

func (s *Service) SignUp(
	ctx context.Context,
	req *connect.Request[authv1.SignUpRequest],
) (*connect.Response[authv1.SignUpResponse], error) {
	email, err := validEmail(req.Msg.GetEmail())
	if err != nil {
		return nil, err
	}
	if err := validPassword(req.Msg.GetPassword()); err != nil {
		return nil, err
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Msg.GetPassword()), bcrypt.DefaultCost)
	if err != nil {
		return nil, rpcerr.Internal(ctx, "hashing password", err)
	}

	user, err := s.queries.CreateUser(ctx, db.CreateUserParams{
		Email:        email,
		PasswordHash: string(hash),
	})
	// Letting the insert fail is what makes the check atomic; looking the
	// address up first would leave room for a second request in between.
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == uniqueViolation {
		return nil, connect.NewError(
			connect.CodeAlreadyExists,
			errors.New("that email already has an account"),
		)
	}
	if err != nil {
		return nil, rpcerr.Internal(ctx, "creating user", err)
	}

	res := connect.NewResponse(&authv1.SignUpResponse{})

	token, err := s.issueToken(ctx, user.ID, res.Header())
	if err != nil {
		return nil, err
	}
	res.Msg.Token = token

	return res, nil
}

func (s *Service) LogIn(
	ctx context.Context,
	req *connect.Request[authv1.LogInRequest],
) (*connect.Response[authv1.LogInResponse], error) {
	email, err := validEmail(req.Msg.GetEmail())
	if err != nil {
		return nil, err
	}
	if err := validPassword(req.Msg.GetPassword()); err != nil {
		return nil, err
	}
	user, err := s.queries.GetUserByEmail(ctx, email)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return nil, rpcerr.Internal(ctx, "looking up user", err)
	}

	hash := []byte(user.PasswordHash)
	if errors.Is(err, pgx.ErrNoRows) {
		hash = dummyHash()
	}

	if bcrypt.CompareHashAndPassword(hash, []byte(req.Msg.GetPassword())) != nil ||
		errors.Is(err, pgx.ErrNoRows) {
		return nil, invalidCredentials()
	}

	res := connect.NewResponse(&authv1.LogInResponse{})

	token, err := s.issueToken(ctx, user.ID, res.Header())
	if err != nil {
		return nil, err
	}
	res.Msg.Token = token

	return res, nil
}

// LogOut deletes the session the request carries and expires the cookie that
// held it. Deleting the row is what makes this mean something: the token is
// signed and cannot be withdrawn, so until the row is gone it still names an
// open session, and a client that kept a copy of it would go on being served.
//
// The procedure needs no token to reach, so the session is read off the
// request itself. A request carrying nothing usable is answered as a success:
// the client is giving its session up either way, and saying which of the two
// happened would only tell an unauthenticated caller whether a token is good.
func (s *Service) LogOut(
	ctx context.Context,
	req *connect.Request[authv1.LogOutRequest],
) (*connect.Response[authv1.LogOutResponse], error) {
	res := connect.NewResponse(&authv1.LogOutResponse{})
	res.Header().Add("Set-Cookie", ClearedSessionCookie(s.secureCookies).String())

	token, ok := RequestToken(req.Header())
	if !ok {
		return res, nil
	}

	userID, sessionID, err := s.issuer.Verify(token)
	if err != nil {
		slog.DebugContext(ctx, "logging out on a token that does not verify", "error", err)

		return res, nil
	}

	// Reported rather than swallowed. The row is what holds the session open,
	// so a client told it had logged out while the row survived would be wrong
	// about the one thing it asked for.
	if err := s.queries.DeleteSession(ctx, db.DeleteSessionParams{
		ID:     sessionID,
		UserID: userID,
	}); err != nil {
		return nil, rpcerr.Internal(ctx, "closing session", err)
	}

	return res, nil
}
