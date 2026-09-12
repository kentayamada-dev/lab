package server

import (
	"context"
	"errors"
	"log/slog"

	"connectrpc.com/connect"

	"example/app/internal/auth"
	"example/app/internal/rpcerr"
)

// Authenticator reads the account out of a bearer token. *auth.Verifier
// satisfies it.
type Authenticator interface {
	Verify(ctx context.Context, token string) (int64, error)
}

// authInterceptor turns away a request that carries no usable token and hands
// the handler of one that does the account it names (auth.UserIDFromContext).
//
// It implements connect.Interceptor in full rather than being a
// connect.UnaryInterceptorFunc, which "has no effect on streaming RPCs": a
// streaming procedure added to a service this guards would otherwise be served
// without any of this running, and would compile and pass the existing tests
// while doing so.
type authInterceptor struct {
	authenticator Authenticator
}

// withAuth guards a service with authenticator.
func withAuth(authenticator Authenticator) connect.Interceptor {
	return authInterceptor{authenticator: authenticator}
}

func (i authInterceptor) WrapUnary(next connect.UnaryFunc) connect.UnaryFunc {
	return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
		token, ok := auth.RequestToken(req.Header())
		if !ok {
			return nil, rpcerr.Unauthenticated()
		}

		userID, err := i.authenticator.Verify(ctx, token)
		if err != nil {
			// Only a verdict on the token turns the client away. A lookup
			// that could not be made says nothing about the token, and
			// answering it with "log in again" would send the client off
			// to fix what is not its problem (auth.ErrRejected).
			if !errors.Is(err, auth.ErrRejected) {
				return nil, rpcerr.Internal(ctx, "verifying the token", err)
			}

			// A rejected token is an ordinary answer to give a client, not
			// a fault worth an error-level line on the server.
			slog.DebugContext(ctx, "rejected a token", "error", err)

			return nil, rpcerr.Unauthenticated()
		}

		return next(auth.ContextWithUserID(ctx, userID), req)
	}
}

// WrapStreamingClient is the client half of the interface, which a handler
// never reaches. It is here because connect.Interceptor asks for it.
func (authInterceptor) WrapStreamingClient(next connect.StreamingClientFunc) connect.StreamingClientFunc {
	return next
}

// WrapStreamingHandler refuses every stream instead of authenticating one.
// Where a token is checked, and what a stream does when it expires halfway
// through, are decisions the first streaming procedure has to make on purpose;
// until one exists, refusing is what keeps the guarded service from quietly
// growing a procedure this never ran on.
func (authInterceptor) WrapStreamingHandler(connect.StreamingHandlerFunc) connect.StreamingHandlerFunc {
	return func(context.Context, connect.StreamingHandlerConn) error {
		return connect.NewError(
			connect.CodeUnimplemented,
			errors.New("this service serves no streaming procedure"),
		)
	}
}
