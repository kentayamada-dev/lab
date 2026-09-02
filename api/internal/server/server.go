// Package server builds the HTTP routes and runs the API server.
package server

import (
	"context"
	"errors"
	"log"
	"net/http"
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

type Server struct {
	httpServer *http.Server
}

func New(addr string, todoService todov1connect.TodoServiceHandler) *Server {
	// Enforces the buf.validate rules declared in the proto.
	validator := validate.NewInterceptor()

	mux := http.NewServeMux()

	path, handler := todov1connect.NewTodoServiceHandler(todoService, connect.WithInterceptors(validator))
	mux.Handle(path, handler)

	registerDocs(mux)

	return &Server{
		httpServer: &http.Server{
			Addr:              addr,
			Handler:           mux,
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
