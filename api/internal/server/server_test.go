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

	srv := httptest.NewServer(New(":0", corsOrigins, handler).httpServer.Handler)
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
	if err := New("not-an-address", nil, stubHandler{}).Run(t.Context()); err == nil {
		t.Error("Run() error = nil, want non-nil")
	}
}

func TestRunShutsDownOnContextCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())

	errCh := make(chan error, 1)
	go func() { errCh <- New("127.0.0.1:0", nil, stubHandler{}).Run(ctx) }()

	cancel()

	if err := <-errCh; err != nil {
		t.Errorf("Run() error = %v, want nil after a graceful shutdown", err)
	}
}

func TestNewServesOpenAPIDocument(t *testing.T) {
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

func TestNewRejectsNonGETOnTheOpenAPIDocument(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	res := do(t, srv, http.MethodPost, "/openapi.yaml", nil)

	if res.StatusCode != http.StatusMethodNotAllowed {
		t.Errorf("status = %d, want %d", res.StatusCode, http.StatusMethodNotAllowed)
	}
}

// The Swagger UI page is served from the docs container's own port
// (docker-compose.yml), so both the fetch of the document and the requests
// "Try it out" sends are cross-origin: the preflight has to be answered and
// the answer has to name the origin, or the browser hides it from the page.
func TestNewAllowsTheConfiguredCORSOrigin(t *testing.T) {
	const origin = "http://localhost:8081"

	srv := newCORSTestServer(t, []string{origin}, stubHandler{})

	pre := preflight(t, srv, origin)
	if pre.StatusCode != http.StatusNoContent {
		t.Fatalf("preflight status = %d, want %d", pre.StatusCode, http.StatusNoContent)
	}
	if got := pre.Header.Get("Access-Control-Allow-Origin"); got != origin {
		t.Errorf("preflight Access-Control-Allow-Origin = %q, want %q", got, origin)
	}
	if got := pre.Header.Get("Access-Control-Allow-Methods"); !strings.Contains(got, http.MethodPost) {
		t.Errorf("preflight Access-Control-Allow-Methods = %q, want it to contain %q", got, http.MethodPost)
	}
	for _, header := range []string{"content-type", "connect-protocol-version"} {
		if got := pre.Header.Get("Access-Control-Allow-Headers"); !strings.Contains(got, header) {
			t.Errorf("preflight Access-Control-Allow-Headers = %q, want it to contain %q", got, header)
		}
	}

	res := getWithOrigin(t, srv, "/openapi.yaml", origin)
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
	srv := newCORSTestServer(t, []string{"http://localhost:8081"}, stubHandler{})

	if got := preflight(t, srv, "http://example.com").Header.Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("Access-Control-Allow-Origin = %q, want it unset", got)
	}
}

// A deployment that runs no docs container configures no origin, and then the
// answers carry no CORS header at all.
func TestNewSendsNoCORSHeaderWithoutAConfiguredOrigin(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

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
// CreateTodo the docs page offers. The requested headers are lower-cased and
// sorted because that is the form a browser sends, and the only form the CORS
// handler matches: given "Content-Type", or the two names in the other order,
// it answers the preflight without the allow headers, exactly as it does for a
// header nobody allowed.
func preflight(t *testing.T, srv *httptest.Server, origin string) *http.Response {
	t.Helper()

	return do(t, srv, http.MethodOptions, "/todo.v1.TodoService/CreateTodo", http.Header{
		"Origin":                         []string{origin},
		"Access-Control-Request-Method":  []string{http.MethodPost},
		"Access-Control-Request-Headers": []string{"connect-protocol-version,content-type"},
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
