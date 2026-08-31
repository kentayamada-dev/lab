package server

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
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

func newTestServer(t *testing.T, handler todov1connect.TodoServiceHandler) *httptest.Server {
	t.Helper()

	srv := httptest.NewServer(New(":0", handler).httpServer.Handler)
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

func TestNewUnknownPath(t *testing.T) {
	res := get(t, newTestServer(t, stubHandler{}), "/todo.v1.TodoService/DeleteTodo")

	if res.StatusCode != http.StatusNotFound {
		t.Errorf("status = %d, want %d", res.StatusCode, http.StatusNotFound)
	}
}

func TestRunInvalidAddress(t *testing.T) {
	if err := New("not-an-address", stubHandler{}).Run(t.Context()); err == nil {
		t.Error("Run() error = nil, want non-nil")
	}
}

func TestRunShutsDownOnContextCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())

	errCh := make(chan error, 1)
	go func() { errCh <- New("127.0.0.1:0", stubHandler{}).Run(ctx) }()

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
