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
	"connectrpc.com/vanguard"

	"example/app/gen/go/todo/v1/todov1connect"
)

const (
	readHeaderTimeout = 10 * time.Second
	readTimeout       = 30 * time.Second
	writeTimeout      = 30 * time.Second
	idleTimeout       = 2 * time.Minute
	shutdownTimeout   = 10 * time.Second
)

// restPrefix is the path prefix of the google.api.http annotations in
// todo.proto. The transcoder is mounted on it, rather than on "/", so that an
// unknown path stays a 404 from the mux, and so that CORS covers the REST
// routes alone (cors.go). An annotation moved outside the prefix fails the
// tests that call the REST routes.
const restPrefix = "/v1/"

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
// the REST routes (cors.go). It fails when the transcoder rejects the service,
// which means the HTTP transcoding annotations in the proto are unusable.
func New(
	addr string,
	corsOrigins []string,
	todoService todov1connect.TodoServiceHandler,
) (*Server, error) {
	// Enforces the buf.validate rules declared in the proto.
	validator := validate.NewInterceptor()

	// The transcoder wraps the Connect handler so the RPCs are reachable over
	// the plain REST routes the google.api.http annotations declare, on top of
	// the Connect procedures the generated clients call.
	transcoder, err := vanguard.NewTranscoder(
		[]*vanguard.Service{
			vanguard.NewService(todov1connect.NewTodoServiceHandler(
				todoService,
				connect.WithInterceptors(validator),
				connect.WithReadMaxBytes(readMaxBytes),
				connect.WithRecover(recoverPanic),
			)),
		},
		// Classifies an unreadable request body as the client's mistake
		// (codec.go).
		vanguard.WithCodec(newJSONCodec),
	)
	if err != nil {
		return nil, err
	}

	mux := http.NewServeMux()
	mux.Handle("/"+todov1connect.TodoServiceName+"/", transcoder)
	mux.Handle(restPrefix, withCORS(corsOrigins, transcoder))

	return &Server{
		httpServer: &http.Server{
			Addr:              addr,
			Handler:           mux,
			ReadHeaderTimeout: readHeaderTimeout,
			ReadTimeout:       readTimeout,
			WriteTimeout:      writeTimeout,
			IdleTimeout:       idleTimeout,
		},
	}, nil
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
