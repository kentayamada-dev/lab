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
	"google.golang.org/protobuf/reflect/protoreflect"

	todov1 "example/app/gen/go/todo/v1"
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

// registerShortPaths mounts every procedure of the service a second time under
// just its method name, so /todo.v1.TodoService/CreateTodo is also reachable as
// /CreateTodo. The canonical procedures stay mounted, since they are what the
// generated clients call. It returns the procedure each short path forwards to,
// keyed by that path, so the OpenAPI document can describe the same routes.
func registerShortPaths(mux *http.ServeMux, prefix string, handler http.Handler) map[string]string {
	methods := todov1.File_todo_v1_todo_proto.Services().
		ByName(protoreflect.FullName(todov1connect.TodoServiceName).Name()).
		Methods()

	shortPaths := make(map[string]string, methods.Len())

	for i := range methods.Len() {
		name := string(methods.Get(i).Name())
		procedure := prefix + name
		short := "/" + name

		shortPaths[short] = procedure

		mux.Handle(short, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// The Connect handler dispatches on the request path, so the
			// canonical procedure has to be put back before it sees the
			// request. RawPath goes with it: it holds the encoded form of the
			// path it was parsed from, which no longer applies.
			r = r.Clone(r.Context())
			r.URL.Path = procedure
			r.URL.RawPath = ""

			handler.ServeHTTP(w, r)
		}))
	}

	return shortPaths
}

func New(addr string, todoService todov1connect.TodoServiceHandler) *Server {
	// Enforces the buf.validate rules declared in the proto.
	validator := validate.NewInterceptor()

	mux := http.NewServeMux()

	prefix, handler := todov1connect.NewTodoServiceHandler(
		todoService,
		connect.WithInterceptors(validator),
		connect.WithReadMaxBytes(readMaxBytes),
		connect.WithRecover(recoverPanic),
	)
	mux.Handle(prefix, handler)

	registerDocs(mux, registerShortPaths(mux, prefix, handler))

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
