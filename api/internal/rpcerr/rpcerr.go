// Package rpcerr turns a failure inside a handler into the error its client
// sees.
package rpcerr

import (
	"context"
	"errors"
	"log/slog"

	"connectrpc.com/connect"
)

// Unauthenticated is the answer to a request that named no account. Both the
// interceptor that checks the token (api/internal/server/auth.go) and the
// handlers that read the account it resolved give it, so what a client is told
// does not depend on which of the two turned it away.
func Unauthenticated() *connect.Error {
	return connect.NewError(
		connect.CodeUnauthenticated,
		errors.New("a valid session or bearer token is required"),
	)
}

// Internal logs the cause and returns a generic error, keeping details such as
// database messages out of the response. A cancelled or expired context is
// reported under its own code: it describes what happened to the request
// rather than a fault on the server, and the handler timeout
// (api/internal/server/timeout.go) reaches the client this way.
func Internal(ctx context.Context, op string, err error) *connect.Error {
	slog.ErrorContext(ctx, op, "error", err)

	switch {
	case errors.Is(err, context.Canceled):
		return connect.NewError(connect.CodeCanceled, errors.New("request cancelled"))
	case errors.Is(err, context.DeadlineExceeded):
		return connect.NewError(connect.CodeDeadlineExceeded, errors.New("request timed out"))
	default:
		return connect.NewError(connect.CodeInternal, errors.New("internal error"))
	}
}
