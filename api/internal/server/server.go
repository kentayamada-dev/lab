// Package server builds the HTTP routes and runs the API server.
package server

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"runtime/debug"
	"time"

	"connectrpc.com/connect"
	"connectrpc.com/otelconnect"
	"connectrpc.com/validate"

	"example/app/gen/go/auth/v1/authv1connect"
	"example/app/gen/go/todo/v1/todov1connect"
)

const (
	readHeaderTimeout = 10 * time.Second
	readTimeout       = 30 * time.Second
	writeTimeout      = 30 * time.Second
	idleTimeout       = 2 * time.Minute
	shutdownTimeout   = 10 * time.Second
)

// readMaxBytes caps a decoded request message. The proto rules are checked
// after decoding, so without this the title limit would not bound the memory a
// request can claim. The largest legitimate request is a title of a thousand
// runes, well inside this.
const readMaxBytes = 64 * 1024

// Pinger reports whether a dependency the server needs is still reachable.
// *pgxpool.Pool satisfies it.
type Pinger interface {
	Ping(ctx context.Context) error
}

// Deps carries what New builds the routes from.
type Deps struct {
	// Addr is the TCP address to listen on.
	Addr string
	// CORSOrigins names the browser origins allowed to call the API from a
	// page they serve (cors.go).
	CORSOrigins []string
	// Health is what GET /healthz pings (health.go).
	Health Pinger
	// Auth serves the AuthService procedures, the only ones reachable without
	// a token.
	Auth authv1connect.AuthServiceHandler
	// Todo serves the TodoService procedures.
	Todo todov1connect.TodoServiceHandler
	// Authenticator checks the bearer token of every TodoService request
	// (auth.go).
	Authenticator Authenticator
}

type Server struct {
	httpServer *http.Server
}

// recoverPanic reports a panicking handler as a generic internal error, so the
// client sees the same answer as any other server-side failure rather than a
// dropped connection.
func recoverPanic(ctx context.Context, spec connect.Spec, _ http.Header, cause any) error {
	slog.ErrorContext(ctx, "panic in handler",
		"procedure", spec.Procedure,
		"cause", cause,
		"stack", string(debug.Stack()),
	)

	return connect.NewError(connect.CodeInternal, errors.New("internal error"))
}

// New builds the routes.
func New(deps Deps) (*Server, error) {
	// Records a span and the RPC metrics of every procedure call against the
	// providers telemetry.Setup installed (api/internal/telemetry).
	otel, err := otelconnect.NewInterceptor()
	if err != nil {
		return nil, err
	}

	timeout := withTimeout(handlerTimeout)
	// Enforces the buf.validate rules declared in the proto.
	validator := validate.NewInterceptor()

	mux := http.NewServeMux()

	// Browsers are authenticated by a cookie the browser attaches by itself
	// (api/internal/auth/cookie.go), so a request from another site would carry
	// it too. Requiring the Connect protocol's own header is what turns those
	// away: a cross-site form cannot set a header at all, and a cross-origin
	// script cannot without a preflight the CORS handler refuses (cors.go).
	// gRPC and gRPC-Web requests are out of its reach for the same reason,
	// their content types being ones no form can send.
	csrf := connect.WithRequireConnectProtocolHeader()

	// Interceptors wrap the handler in the order they are given, so the span
	// covers the whole call and the deadline covers validation too. AuthService
	// hands out the sessions, which makes it the one service reachable without
	// one; on TodoService the token is checked before the request is examined
	// any further.
	authPath, authHandler := authv1connect.NewAuthServiceHandler(
		deps.Auth,
		connect.WithInterceptors(otel, timeout, validator),
		connect.WithReadMaxBytes(readMaxBytes),
		connect.WithRecover(recoverPanic),
		csrf,
	)
	mux.Handle(authPath, authHandler)

	todoPath, todoHandler := todov1connect.NewTodoServiceHandler(
		deps.Todo,
		connect.WithInterceptors(otel, timeout, withAuth(deps.Authenticator), validator),
		connect.WithReadMaxBytes(readMaxBytes),
		connect.WithRecover(recoverPanic),
		csrf,
	)
	mux.Handle(todoPath, todoHandler)

	registerOpenAPI(mux)
	registerHealth(mux, deps.Health)

	return &Server{
		httpServer: &http.Server{
			Addr:              deps.Addr,
			Handler:           withCORS(deps.CORSOrigins, mux),
			Protocols:         protocols(),
			ReadHeaderTimeout: readHeaderTimeout,
			ReadTimeout:       readTimeout,
			WriteTimeout:      writeTimeout,
			IdleTimeout:       idleTimeout,
		},
	}, nil
}

// Run serves until ctx is cancelled, then shuts down gracefully.
func (s *Server) Run(ctx context.Context) error {
	slog.InfoContext(ctx, "listening", "addr", s.httpServer.Addr)

	errCh := make(chan error, 1)
	go func() { errCh <- s.httpServer.ListenAndServe() }()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	shutdownErr := s.httpServer.Shutdown(shutdownCtx)

	// Shutdown makes ListenAndServe return right away, so this receive cannot
	// block; anything but ErrServerClosed is a serve failure that raced the
	// cancellation.
	if err := <-errCh; !errors.Is(err, http.ErrServerClosed) {
		return err
	}

	return shutdownErr
}
