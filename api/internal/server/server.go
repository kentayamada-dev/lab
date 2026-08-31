// Package server builds the HTTP routes and runs the API server.
package server

import (
	"context"
	"log"
	"net/http"
	"time"

	"example/app/gen/go/todo/v1/todov1connect"
)

const (
	readHeaderTimeout = 10 * time.Second
	idleTimeout       = 2 * time.Minute
	shutdownTimeout   = 10 * time.Second
)

type Server struct {
	httpServer *http.Server
}

func New(addr string, todoService todov1connect.TodoServiceHandler) *Server {
	mux := http.NewServeMux()

	path, handler := todov1connect.NewTodoServiceHandler(todoService)
	mux.Handle(path, handler)

	registerDocs(mux)

	return &Server{
		httpServer: &http.Server{
			Addr:              addr,
			Handler:           mux,
			ReadHeaderTimeout: readHeaderTimeout,
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

	return s.httpServer.Shutdown(shutdownCtx)
}
