package server

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"connectrpc.com/connect"
	"github.com/google/go-cmp/cmp"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/testing/protocmp"

	"example/app/gen"
	todov1 "example/app/gen/go/todo/v1"
	"example/app/gen/go/todo/v1/todov1connect"
)

type stubHandler struct {
	todov1connect.UnimplementedTodoServiceHandler
}

func (stubHandler) CreateTodo(
	_ context.Context,
	req *connect.Request[todov1.CreateTodoRequest],
) (*connect.Response[todov1.CreateTodoResponse], error) {
	return connect.NewResponse(&todov1.CreateTodoResponse{
		Todo: &todov1.Todo{Id: 1, Title: req.Msg.GetTitle()},
	}), nil
}

type panicHandler struct {
	todov1connect.UnimplementedTodoServiceHandler
}

func (panicHandler) ListTodos(
	context.Context,
	*connect.Request[todov1.ListTodosRequest],
) (*connect.Response[todov1.ListTodosResponse], error) {
	panic("handler exploded")
}

// recorder keeps the request the called method received, so a test can assert
// how a REST route mapped the path, the query string and the body onto it.
type recorder struct {
	todov1connect.UnimplementedTodoServiceHandler

	got proto.Message
}

func (r *recorder) CreateTodo(
	_ context.Context,
	req *connect.Request[todov1.CreateTodoRequest],
) (*connect.Response[todov1.CreateTodoResponse], error) {
	r.got = req.Msg

	return connect.NewResponse(&todov1.CreateTodoResponse{}), nil
}

func (r *recorder) ListTodos(
	_ context.Context,
	req *connect.Request[todov1.ListTodosRequest],
) (*connect.Response[todov1.ListTodosResponse], error) {
	r.got = req.Msg

	return connect.NewResponse(&todov1.ListTodosResponse{}), nil
}

func (r *recorder) UpdateTodo(
	_ context.Context,
	req *connect.Request[todov1.UpdateTodoRequest],
) (*connect.Response[todov1.UpdateTodoResponse], error) {
	r.got = req.Msg

	return connect.NewResponse(&todov1.UpdateTodoResponse{}), nil
}

func (r *recorder) DeleteTodo(
	_ context.Context,
	req *connect.Request[todov1.DeleteTodoRequest],
) (*connect.Response[todov1.DeleteTodoResponse], error) {
	r.got = req.Msg

	return connect.NewResponse(&todov1.DeleteTodoResponse{}), nil
}

func newServer(t *testing.T, addr string, handler todov1connect.TodoServiceHandler) *Server {
	t.Helper()

	srv, err := New(addr, handler)
	if err != nil {
		t.Fatalf("New() error = %v, want nil", err)
	}

	return srv
}

func newTestServer(t *testing.T, handler todov1connect.TodoServiceHandler) *httptest.Server {
	t.Helper()

	srv := httptest.NewServer(newServer(t, ":0", handler).httpServer.Handler)
	t.Cleanup(srv.Close)

	return srv
}

func TestNewServesTodoService(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

	res, err := client.CreateTodo(
		t.Context(),
		connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"}),
	)
	if err != nil {
		t.Fatalf("CreateTodo() error = %v, want nil", err)
	}

	if diff := cmp.Diff("buy milk", res.Msg.GetTodo().GetTitle()); diff != "" {
		t.Errorf("CreateTodo() todo title (-want +got):\n%s", diff)
	}
}

// The REST routes come from the google.api.http annotations in todo.proto, and
// the transcoder has to map each one back onto the request message: the body
// for a create, the query string for a list, the path for an id. A route moved
// outside restPrefix stops reaching the transcoder and fails here.
func TestNewServesTheAnnotatedRESTRoutes(t *testing.T) {
	tests := map[string]struct {
		method string
		path   string
		body   string
		want   proto.Message
	}{
		"create takes the title from the body": {
			method: http.MethodPost,
			path:   "/v1/todos",
			body:   `{"title":"buy milk"}`,
			want:   &todov1.CreateTodoRequest{Title: "buy milk"},
		},
		"list takes the page from the query string": {
			method: http.MethodGet,
			path:   "/v1/todos?pageSize=5&pageToken=42",
			want:   &todov1.ListTodosRequest{PageSize: 5, PageToken: "42"},
		},
		"update takes the id from the path and the fields from the body": {
			method: http.MethodPatch,
			path:   "/v1/todos/7",
			body:   `{"done":true}`,
			want:   &todov1.UpdateTodoRequest{Id: 7, Done: proto.Bool(true)},
		},
		"delete takes the id from the path": {
			method: http.MethodDelete,
			path:   "/v1/todos/9",
			want:   &todov1.DeleteTodoRequest{Id: 9},
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			handler := &recorder{}
			srv := newTestServer(t, handler)

			req, err := http.NewRequestWithContext(
				t.Context(), tt.method, srv.URL+tt.path, strings.NewReader(tt.body),
			)
			if err != nil {
				t.Fatalf("building the request: %v", err)
			}
			req.Header.Set("Content-Type", "application/json")

			res, err := srv.Client().Do(req)
			if err != nil {
				t.Fatalf("%s %s: %v", tt.method, tt.path, err)
			}
			t.Cleanup(func() { res.Body.Close() })

			if res.StatusCode != http.StatusOK {
				t.Fatalf("status = %d, want %d, body: %s",
					res.StatusCode, http.StatusOK, readBody(t, res))
			}
			if diff := cmp.Diff(tt.want, handler.got, protocmp.Transform()); diff != "" {
				t.Errorf("request the handler received (-want +got):\n%s", diff)
			}
		})
	}
}

func TestNewUnimplementedMethod(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

	_, err := client.ListTodos(t.Context(), connect.NewRequest(&todov1.ListTodosRequest{}))
	if got := connect.CodeOf(err); got != connect.CodeUnimplemented {
		t.Errorf("ListTodos() code = %v, want %v", got, connect.CodeUnimplemented)
	}
}

// The stub answers every CreateTodo with a success, so a rejection here can
// only come from the validate interceptor.
func TestNewEnforcesProtoValidation(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

	_, err := client.CreateTodo(
		t.Context(),
		connect.NewRequest(&todov1.CreateTodoRequest{Title: "   "}),
	)
	if got := connect.CodeOf(err); got != connect.CodeInvalidArgument {
		t.Errorf("CreateTodo() code = %v, want %v", got, connect.CodeInvalidArgument)
	}
}

// The proto rules apply to the trimmed title, the same value the service
// checks, so surrounding whitespace does not count towards the limit. The
// full-width space pins the trimming to Unicode whitespace, as in the
// service's strings.TrimSpace, rather than ASCII only.
func TestNewProtoValidationTrimsTitle(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

	tests := map[string]struct {
		title    string
		wantCode connect.Code
	}{
		"at the limit with surrounding whitespace": {
			title:    " " + strings.Repeat("あ", 1000) + "\n",
			wantCode: 0,
		},
		"at the limit with surrounding full-width spaces": {
			title:    "　" + strings.Repeat("あ", 1000) + "　",
			wantCode: 0,
		},
		"one over the limit": {
			title:    strings.Repeat("あ", 1001),
			wantCode: connect.CodeInvalidArgument,
		},
		"blank after trimming full-width spaces": {
			title:    "　　",
			wantCode: connect.CodeInvalidArgument,
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			_, err := client.CreateTodo(
				t.Context(),
				connect.NewRequest(&todov1.CreateTodoRequest{Title: tt.title}),
			)
			if tt.wantCode == 0 {
				if err != nil {
					t.Errorf("CreateTodo() error = %v, want nil", err)
				}
			} else if got := connect.CodeOf(err); got != tt.wantCode {
				t.Errorf("CreateTodo() code = %v, want %v", got, tt.wantCode)
			}
		})
	}
}

// The stub implements neither DeleteTodo nor ListTodos, so a request that
// satisfies the proto rules comes back unimplemented; invalid_argument can
// only come from the validate interceptor.
func TestNewProtoValidationRejectsUnusableIDs(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

	tests := map[string]struct {
		id       int64
		wantCode connect.Code
	}{
		"the first id an identity column hands out": {
			id:       1,
			wantCode: connect.CodeUnimplemented,
		},
		"zero": {
			id:       0,
			wantCode: connect.CodeInvalidArgument,
		},
		"negative": {
			id:       -1,
			wantCode: connect.CodeInvalidArgument,
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			_, err := client.DeleteTodo(
				t.Context(),
				connect.NewRequest(&todov1.DeleteTodoRequest{Id: tt.id}),
			)
			if got := connect.CodeOf(err); got != tt.wantCode {
				t.Errorf("DeleteTodo() code = %v, want %v", got, tt.wantCode)
			}
		})
	}
}

// A page token spells a todo id, so the rule has to draw the line where an
// int64 does: everything it accepts must survive the service's ParseInt.
func TestNewProtoValidationPageToken(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

	tests := map[string]struct {
		token    string
		wantCode connect.Code
	}{
		"empty starts at the first page": {
			token:    "",
			wantCode: connect.CodeUnimplemented,
		},
		"a token the service handed out": {
			token:    "42",
			wantCode: connect.CodeUnimplemented,
		},
		"the largest int64": {
			token:    "9223372036854775807",
			wantCode: connect.CodeUnimplemented,
		},
		"one past the largest int64": {
			token:    "9223372036854775808",
			wantCode: connect.CodeInvalidArgument,
		},
		"nineteen nines": {
			token:    "9999999999999999999",
			wantCode: connect.CodeInvalidArgument,
		},
		"twenty digits": {
			token:    "12345678901234567890",
			wantCode: connect.CodeInvalidArgument,
		},
		"zero": {
			token:    "0",
			wantCode: connect.CodeInvalidArgument,
		},
		"a leading zero": {
			token:    "042",
			wantCode: connect.CodeInvalidArgument,
		},
		"not a number": {
			token:    "abc",
			wantCode: connect.CodeInvalidArgument,
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			_, err := client.ListTodos(
				t.Context(),
				connect.NewRequest(&todov1.ListTodosRequest{PageToken: tt.token}),
			)
			if got := connect.CodeOf(err); got != tt.wantCode {
				t.Errorf("ListTodos() code = %v, want %v", got, tt.wantCode)
			}
		})
	}
}

// A panicking handler must reach the client as an ordinary internal error,
// carrying no more detail than any other server-side failure.
func TestNewRecoversFromAPanickingHandler(t *testing.T) {
	srv := newTestServer(t, panicHandler{})

	client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

	_, err := client.ListTodos(t.Context(), connect.NewRequest(&todov1.ListTodosRequest{}))
	if got := connect.CodeOf(err); got != connect.CodeInternal {
		t.Errorf("ListTodos() code = %v, want %v", got, connect.CodeInternal)
	}

	var connectErr *connect.Error
	if !errors.As(err, &connectErr) {
		t.Fatalf("ListTodos() error = %v, want a *connect.Error", err)
	}
	if diff := cmp.Diff("internal error", connectErr.Message()); diff != "" {
		t.Errorf("client-facing message (-want +got):\n%s", diff)
	}
}

// The proto rules are checked after decoding, so an oversized message has to be
// stopped by the handler's read limit rather than by validation.
func TestNewRejectsAnOversizedMessage(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

	_, err := client.CreateTodo(
		t.Context(),
		connect.NewRequest(&todov1.CreateTodoRequest{Title: strings.Repeat("a", readMaxBytes+1)}),
	)
	if got := connect.CodeOf(err); got != connect.CodeResourceExhausted {
		t.Errorf("CreateTodo() code = %v, want %v", got, connect.CodeResourceExhausted)
	}
}

func TestNewUnknownPath(t *testing.T) {
	res := get(t, newTestServer(t, stubHandler{}), "/todo.v1.TodoService/PurgeTodos")

	if res.StatusCode != http.StatusNotFound {
		t.Errorf("status = %d, want %d", res.StatusCode, http.StatusNotFound)
	}
}

func TestRunInvalidAddress(t *testing.T) {
	if err := newServer(t, "not-an-address", stubHandler{}).Run(t.Context()); err == nil {
		t.Error("Run() error = nil, want non-nil")
	}
}

func TestRunShutsDownOnContextCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())

	errCh := make(chan error, 1)
	srv := newServer(t, "127.0.0.1:0", stubHandler{})

	go func() { errCh <- srv.Run(ctx) }()

	cancel()

	if err := <-errCh; err != nil {
		t.Errorf("Run() error = %v, want nil after a graceful shutdown", err)
	}
}

func TestDocsServesSwaggerUI(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	res := get(t, srv, "/docs")
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want %d", res.StatusCode, http.StatusOK)
	}

	if got, want := res.Header.Get("Content-Type"), "text/html; charset=utf-8"; got != want {
		t.Errorf("Content-Type = %q, want %q", got, want)
	}
	if !cmp.Equal(swaggerHTML, readBody(t, res)) {
		t.Error("body does not match the embedded swagger.html")
	}
}

func TestDocsServesSwaggerAssets(t *testing.T) {
	tests := map[string]struct {
		path        string
		contentType string
		body        []byte
	}{
		"stylesheet": {
			path:        "/docs/swagger-ui.css",
			contentType: "text/css; charset=utf-8",
			body:        swaggerCSS,
		},
		"bundle": {
			path:        "/docs/swagger-ui-bundle.js",
			contentType: "text/javascript; charset=utf-8",
			body:        swaggerJS,
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			srv := newTestServer(t, stubHandler{})

			res := get(t, srv, tt.path)
			if res.StatusCode != http.StatusOK {
				t.Fatalf("status = %d, want %d", res.StatusCode, http.StatusOK)
			}
			if got := res.Header.Get("Content-Type"); got != tt.contentType {
				t.Errorf("Content-Type = %q, want %q", got, tt.contentType)
			}
			if !cmp.Equal(tt.body, readBody(t, res)) {
				t.Error("body does not match the embedded asset")
			}
		})
	}
}

func TestDocsServesOpenAPIDocument(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	res := get(t, srv, "/openapi.yaml")
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want %d", res.StatusCode, http.StatusOK)
	}

	if got, want := res.Header.Get("Content-Type"), "application/yaml"; got != want {
		t.Errorf("Content-Type = %q, want %q", got, want)
	}
	if !cmp.Equal(gen.OpenAPIYAML, readBody(t, res)) {
		t.Error("body does not match the embedded OpenAPI document")
	}
}

func TestDocsRejectsNonGET(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	res, err := srv.Client().Post(srv.URL+"/docs", "text/plain", nil)
	if err != nil {
		t.Fatalf("POST /docs: %v", err)
	}
	t.Cleanup(func() { res.Body.Close() })

	if res.StatusCode != http.StatusMethodNotAllowed {
		t.Errorf("status = %d, want %d", res.StatusCode, http.StatusMethodNotAllowed)
	}
}

func get(t *testing.T, srv *httptest.Server, path string) *http.Response {
	t.Helper()

	res, err := srv.Client().Get(srv.URL + path)
	if err != nil {
		t.Fatalf("GET %s: %v", path, err)
	}
	t.Cleanup(func() { res.Body.Close() })

	return res
}

func readBody(t *testing.T, res *http.Response) []byte {
	t.Helper()

	body, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatalf("reading body: %v", err)
	}

	return body
}
