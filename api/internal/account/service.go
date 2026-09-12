package account

import (
	"context"
	"errors"

	"connectrpc.com/connect"
	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
	"google.golang.org/protobuf/types/known/timestamppb"

	"example/app/gen/db"
	accountv1 "example/app/gen/go/account/v1"
	"example/app/internal/auth"
	"example/app/internal/rpcerr"
)

type Querier interface {
	GetUserByID(ctx context.Context, id int64) (db.User, error)
	CloseAccount(ctx context.Context, id int64) (db.CloseAccountRow, error)
}

type Service struct {
	queries Querier
	// secureCookies withholds the session cookie from plain http, and has to
	// match what issued it or the browser keeps the cookie being cleared
	// (api/internal/auth/cookie.go).
	secureCookies bool
}

func NewService(queries Querier, secureCookies bool) *Service {
	return &Service{queries: queries, secureCookies: secureCookies}
}

// DeleteAccount closes the account the request was authenticated as, which
// ends its sessions in the same statement (api/queries/users.sql), and answers
// with the instant the data behind it is erased.
//
// The password is asked for again because the session is not enough to spend
// something this final on. What that guards against is a session being used by
// somebody it was not issued to, so the answer to a wrong one is the same
// unauthenticated the interceptor gives a bad token: the caller has already
// proved which account it is asking about, and there is nothing further to
// tell it.
func (s *Service) DeleteAccount(
	ctx context.Context,
	req *connect.Request[accountv1.DeleteAccountRequest],
) (*connect.Response[accountv1.DeleteAccountResponse], error) {
	userID, ok := auth.UserIDFromContext(ctx)
	if !ok {
		return nil, rpcerr.Unauthenticated()
	}

	user, err := s.queries.GetUserByID(ctx, userID)
	// The account was there a moment ago, the token having just been verified
	// against one of its sessions, so this is a request that raced another
	// closing it. Nothing is left to close either way.
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, rpcerr.Unauthenticated()
	}
	if err != nil {
		return nil, rpcerr.Internal(ctx, "looking up account", err)
	}

	if bcrypt.CompareHashAndPassword(
		[]byte(user.PasswordHash),
		[]byte(req.Msg.GetPassword()),
	) != nil {
		return nil, rpcerr.Unauthenticated()
	}

	closed, err := s.queries.CloseAccount(ctx, userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, rpcerr.Unauthenticated()
	}
	if err != nil {
		return nil, rpcerr.Internal(ctx, "closing account", err)
	}
	// Written by the database, so the countdown starts from the instant the row
	// records rather than from whatever this process thinks the time is.
	if !closed.DeletedAt.Valid {
		return nil, rpcerr.Internal(
			ctx, "closing account", errors.New("the closed row carries no instant"),
		)
	}

	res := connect.NewResponse(&accountv1.DeleteAccountResponse{
		PurgeAt: timestamppb.New(PurgeAt(closed.DeletedAt.Time)),
	})
	// The sessions are gone, so the cookie names one that no longer exists.
	// Expiring it is what stops the browser sending it, which a script on the
	// page cannot do for itself (api/internal/auth/cookie.go).
	res.Header().Add("Set-Cookie", auth.ClearedSessionCookie(s.secureCookies).String())

	return res, nil
}
