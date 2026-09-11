// Package server builds the HTTP routes and runs the API server.
package server

import (
	"context"
	"errors"
	"log"
	"net/http"
	"runtime/debug"
	"time"

	"connectrpc.com/connect"
	"connectrpc.com/validate"

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

type Server struct {
	httpServer *http.Server
}

// recoverPanic reports a panicking handler as a generic internal error, so the
// client sees the same answer as any other server-side failure rather than a
// dropped connection.
func recoverPanic(_ context.Context, spec connect.Spec, _ http.Header, cause any) error {
	log.Printf("panic in %s: %v\n%s", spec.Procedure, cause, debug.Stack())

	return connect.NewError(connect.CodeInternal, errors.New("internal error"))
}

// New builds the routes. corsOrigins names the browser origins allowed to call
// the API from a page they serve (cors.go).
func New(
	addr string,
	corsOrigins []string,
	todoService todov1connect.TodoServiceHandler,
) *Server {
	// Enforces the buf.validate rules declared in the proto.
	validator := validate.NewInterceptor()

	mux := http.NewServeMux()

	path, handler := todov1connect.NewTodoServiceHandler(
		todoService,
		connect.WithInterceptors(validator),
		connect.WithReadMaxBytes(readMaxBytes),
		connect.WithRecover(recoverPanic),
	)
	mux.Handle(path, handler)

	registerOpenAPI(mux)

	return &Server{
		httpServer: &http.Server{
			Addr:              addr,
			Handler:           withCORS(corsOrigins, mux),
			ReadHeaderTimeout: readHeaderTimeout,
			ReadTimeout:       readTimeout,
			WriteTimeout:      writeTimeout,
			IdleTimeout:       idleTimeout,
		},
	}
}

// Run serves until ctx is cancelled, then shuts down gracefully.
func (s *Server) Run(ctx context.Context) error {
	log.Println("listening on " + s.httpServer.Addr)

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
