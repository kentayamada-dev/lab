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

func newServer(
	t *testing.T,
	addr string,
	corsOrigins []string,
	handler todov1connect.TodoServiceHandler,
) *Server {
	t.Helper()

	srv, err := New(addr, corsOrigins, handler)
	if err != nil {
		t.Fatalf("New() error = %v, want nil", err)
	}

	return srv
}

func newTestServer(t *testing.T, handler todov1connect.TodoServiceHandler) *httptest.Server {
	t.Helper()

	return newCORSTestServer(t, nil, handler)
}

func newCORSTestServer(
	t *testing.T,
	corsOrigins []string,
	handler todov1connect.TodoServiceHandler,
) *httptest.Server {
	t.Helper()

	srv := httptest.NewServer(newServer(t, ":0", corsOrigins, handler).httpServer.Handler)
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
	if err := newServer(t, "not-an-address", nil, stubHandler{}).Run(t.Context()); err == nil {
		t.Error("Run() error = nil, want non-nil")
	}
}

func TestRunShutsDownOnContextCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())

	errCh := make(chan error, 1)
	srv := newServer(t, "127.0.0.1:0", nil, stubHandler{})

	go func() { errCh <- srv.Run(ctx) }()

	cancel()

	if err := <-errCh; err != nil {
		t.Errorf("Run() error = %v, want nil after a graceful shutdown", err)
	}
}

// A body the codec cannot read is the client's mistake. On a route that merges
// a path variable into the body the transcoder unmarshals it itself and leaves
// the code of the error unset, which the REST protocol answers as a 500 with
// the unknown code; codec.go is what turns it into this 400. The same body on
// "POST /v1/todos" is classified by connect-go and covers the other path.
func TestNewRejectsAnUnreadableRESTBody(t *testing.T) {
	tests := map[string]struct {
		method string
		path   string
		body   string
	}{
		"truncated body merged with a path variable": {
			method: http.MethodPatch,
			path:   "/v1/todos/1",
			body:   `{"done":true`,
		},
		"wrong field type merged with a path variable": {
			method: http.MethodPatch,
			path:   "/v1/todos/1",
			body:   `{"done":"yes"}`,
		},
		"truncated body passed on as it is": {
			method: http.MethodPost,
			path:   "/v1/todos",
			body:   `{"title":"buy milk`,
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			srv := newTestServer(t, &recorder{})

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

			if res.StatusCode != http.StatusBadRequest {
				t.Errorf("status = %d, want %d, body: %s",
					res.StatusCode, http.StatusBadRequest, readBody(t, res))
			}
		})
	}
}

// The docs page is served from the docs container's own port
// (docker-compose.yml), so every request it sends to a REST route is
// cross-origin: the preflight has to be answered and the answer has to name the
// origin, or the browser hides it from the page.
func TestNewAllowsTheConfiguredCORSOrigin(t *testing.T) {
	const origin = "http://localhost:8081"

	srv := newCORSTestServer(t, []string{origin}, &recorder{})

	pre := preflight(t, srv, origin)
	if pre.StatusCode != http.StatusNoContent {
		t.Fatalf("preflight status = %d, want %d", pre.StatusCode, http.StatusNoContent)
	}
	if got := pre.Header.Get("Access-Control-Allow-Origin"); got != origin {
		t.Errorf("preflight Access-Control-Allow-Origin = %q, want %q", got, origin)
	}
	if got := pre.Header.Get("Access-Control-Allow-Methods"); !strings.Contains(got, http.MethodPatch) {
		t.Errorf("preflight Access-Control-Allow-Methods = %q, want it to contain %q", got, http.MethodPatch)
	}
	if got := pre.Header.Get("Access-Control-Allow-Headers"); !strings.Contains(got, "content-type") {
		t.Errorf("preflight Access-Control-Allow-Headers = %q, want it to contain %q", got, "content-type")
	}

	res := getWithOrigin(t, srv, "/v1/todos", origin)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want %d", res.StatusCode, http.StatusOK)
	}
	if got := res.Header.Get("Access-Control-Allow-Origin"); got != origin {
		t.Errorf("Access-Control-Allow-Origin = %q, want %q", got, origin)
	}
}

// Every origin but the configured ones is answered without the header, which is
// what makes the browser drop the answer.
func TestNewRefusesAnUnconfiguredCORSOrigin(t *testing.T) {
	srv := newCORSTestServer(t, []string{"http://localhost:8081"}, &recorder{})

	if got := preflight(t, srv, "http://example.com").Header.Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("Access-Control-Allow-Origin = %q, want it unset", got)
	}
}

// A deployment that runs no docs container configures no origin, and then the
// routes carry no CORS header at all.
func TestNewSendsNoCORSHeaderWithoutAConfiguredOrigin(t *testing.T) {
	srv := newTestServer(t, &recorder{})

	if got := preflight(t, srv, "http://localhost:8081").Header.Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("Access-Control-Allow-Origin = %q, want it unset", got)
	}
}

func get(t *testing.T, srv *httptest.Server, path string) *http.Response {
	t.Helper()

	return do(t, srv, http.MethodGet, path, nil)
}

func getWithOrigin(t *testing.T, srv *httptest.Server, path, origin string) *http.Response {
	t.Helper()

	return do(t, srv, http.MethodGet, path, http.Header{"Origin": []string{origin}})
}

// preflight sends the OPTIONS request a browser sends ahead of the cross-origin
// PATCH the docs page offers for /v1/todos/{id}. The requested header is
// lower-cased because that is the form a browser sends, and the form the CORS
// handler matches: given "Content-Type" it answers the preflight without the
// allow headers, exactly as it does for a header nobody allowed.
func preflight(t *testing.T, srv *httptest.Server, origin string) *http.Response {
	t.Helper()

	return do(t, srv, http.MethodOptions, "/v1/todos/1", http.Header{
		"Origin":                         []string{origin},
		"Access-Control-Request-Method":  []string{http.MethodPatch},
		"Access-Control-Request-Headers": []string{"content-type"},
	})
}

func do(
	t *testing.T,
	srv *httptest.Server,
	method, path string,
	header http.Header,
) *http.Response {
	t.Helper()

	req, err := http.NewRequestWithContext(t.Context(), method, srv.URL+path, nil)
	if err != nil {
		t.Fatalf("building %s %s: %v", method, path, err)
	}
	if header != nil {
		req.Header = header
	}

	res, err := srv.Client().Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
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
