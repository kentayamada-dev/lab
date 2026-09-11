package auth

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"connectrpc.com/connect"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
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

// validEmail lower-cases the address so that addresses differing only in case
// are one account, and rejects what could not be one. The proto field declares
// the same rules, enforced by the server's validate interceptor; the check
// here keeps the service safe on its own.
func validEmail(raw string) (string, error) {
	email := strings.ToLower(raw)
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

// issueToken signs a token for the account, puts it on the response as the
// session cookie, and returns it for the clients that carry it themselves.
func (s *Service) issueToken(
	ctx context.Context,
	userID int64,
	header http.Header,
) (*authv1.Token, error) {
	accessToken, expiresAt, err := s.issuer.Issue(userID, time.Now())
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

// LogOut expires the session cookie. It answers the same way whether or not
// the request carried one: there is nothing to report about a session the
// client is giving up anyway.
func (s *Service) LogOut(
	_ context.Context,
	_ *connect.Request[authv1.LogOutRequest],
) (*connect.Response[authv1.LogOutResponse], error) {
	res := connect.NewResponse(&authv1.LogOutResponse{})
	res.Header().Add("Set-Cookie", clearedSessionCookie(s.secureCookies).String())

	return res, nil
}
