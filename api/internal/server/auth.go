package server

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"connectrpc.com/connect"

	"example/app/internal/auth"
	"example/app/internal/rpcerr"
)

// bearerPrefix is the authentication scheme the Authorization header has to
// name. RFC 9110 makes the scheme case-insensitive, so it is matched that way.
const bearerPrefix = "bearer "

// Authenticator reads the account out of a bearer token. *auth.Verifier
// satisfies it.
type Authenticator interface {
	Verify(ctx context.Context, token string) (int64, error)
}

// bearerToken pulls the token out of an Authorization header value.
func bearerToken(header string) (string, bool) {
	if len(header) < len(bearerPrefix) || !strings.EqualFold(header[:len(bearerPrefix)], bearerPrefix) {
		return "", false
	}

	token := strings.TrimSpace(header[len(bearerPrefix):])

	return token, token != ""
}

// sessionToken pulls the token out of the session cookie
// (api/internal/auth/cookie.go).
func sessionToken(header http.Header) (string, bool) {
	for _, line := range header.Values("Cookie") {
		cookies, err := http.ParseCookie(line)
		if err != nil {
			continue
		}

		for _, cookie := range cookies {
			if cookie.Name == auth.SessionCookieName && cookie.Value != "" {
				return cookie.Value, true
			}
		}
	}

	return "", false
}

// requestToken takes the token a request is authenticated by. The Authorization
// header comes first, so a client that names one explicitly is not overruled by
// a cookie its browser attached on its own; a browser sends no header and is
// authenticated by the cookie alone.
func requestToken(header http.Header) (string, bool) {
	if token, ok := bearerToken(header.Get("Authorization")); ok {
		return token, true
	}

	return sessionToken(header)
}

// withAuth turns away a request that carries no usable token and hands the
// handler of one that does the account it names (auth.UserIDFromContext).
func withAuth(authenticator Authenticator) connect.UnaryInterceptorFunc {
	return func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			token, ok := requestToken(req.Header())
			if !ok {
				return nil, rpcerr.Unauthenticated()
			}

			userID, err := authenticator.Verify(ctx, token)
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
}
