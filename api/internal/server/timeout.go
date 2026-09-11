package server

import (
	"context"
	"time"

	"connectrpc.com/connect"
)

// handlerTimeout caps how long one procedure call may run. The Server's read
// and write timeouts are deadlines on the connection, not on the handler:
// neither cancels the context a query runs under, so without this a client
// willing to wait could hold a pool connection indefinitely.
const handlerTimeout = 15 * time.Second

// withTimeout bounds every call by d. Connect turns a client's
// Connect-Timeout-Ms into a context deadline, and context.WithTimeout keeps
// the earlier of the two, so a client asking for less still gets what it asked
// for while one asking for more is cut back to d.
func withTimeout(d time.Duration) connect.UnaryInterceptorFunc {
	return func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			ctx, cancel := context.WithTimeout(ctx, d)
			defer cancel()

			return next(ctx, req)
		}
	}
}
