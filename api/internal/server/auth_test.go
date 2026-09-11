package server

import (
	"errors"
	"net/http"
	"strings"
	"testing"

	"connectrpc.com/connect"
	"github.com/google/go-cmp/cmp"

	authv1 "example/app/gen/go/auth/v1"
	"example/app/gen/go/auth/v1/authv1connect"
	todov1 "example/app/gen/go/todo/v1"
	"example/app/gen/go/todo/v1/todov1connect"
	"example/app/internal/auth"
)

// A browser sends no Authorization header: what authenticates it is the
// session cookie the login response set (api/internal/auth/cookie.go).
func TestNewAuthenticatesBySessionCookie(t *testing.T) {
	srv := newTestServer(t, userIDHandler{})

	client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

	req := connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"})
	req.Header().Set("Cookie", auth.SessionCookieName+"="+testToken)

	res, err := client.CreateTodo(t.Context(), req)
	if err != nil {
		t.Fatalf("CreateTodo() error = %v, want nil", err)
	}

	if got := res.Msg.GetTodo().GetId(); got != testUserID {
		t.Errorf("handler saw account %d, want %d", got, testUserID)
	}
}

// A cookie left over from another session must not override a token the client
// named on purpose.
func TestNewPrefersTheAuthorizationHeaderOverTheCookie(t *testing.T) {
	srv := newTestServer(t, userIDHandler{})

	client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

	req := connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"})
	req.Header().Set("Authorization", "Bearer "+testToken)
	req.Header().Set("Cookie", auth.SessionCookieName+"=not-the-token")

	if _, err := client.CreateTodo(t.Context(), req); err != nil {
		t.Errorf("CreateTodo() error = %v, want the header to be what counts", err)
	}
}

func TestNewRefusesAnUnusableSessionCookie(t *testing.T) {
	tests := map[string]string{
		"another cookie entirely": "somethingelse=" + testToken,
		"an empty session":        auth.SessionCookieName + "=",
		"a token nobody issued":   auth.SessionCookieName + "=not-the-token",
	}

	srv := newTestServer(t, panicOnCallHandler{t: t})

	for name, cookie := range tests {
		t.Run(name, func(t *testing.T) {
			client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

			req := connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"})
			req.Header().Set("Cookie", cookie)

			_, err := client.CreateTodo(t.Context(), req)
			if got := connect.CodeOf(err); got != connect.CodeUnauthenticated {
				t.Errorf("CreateTodo() code = %v, want %v", got, connect.CodeUnauthenticated)
			}
		})
	}
}

// The browser attaches the session cookie to a request another site started
// just as readily as to one of ours. What separates them is this header: a
// cross-site form cannot set it, and a cross-origin script cannot without a
// preflight the CORS handler refuses. Sending the request by hand, without it,
// is the same shape a forged one would have.
func TestNewRefusesAConnectRequestWithoutTheProtocolHeader(t *testing.T) {
	srv := newTestServer(t, panicOnCallHandler{t: t})

	req, err := http.NewRequestWithContext(
		t.Context(),
		http.MethodPost,
		srv.URL+"/todo.v1.TodoService/CreateTodo",
		strings.NewReader(`{"title":"buy milk"}`),
	)
	if err != nil {
		t.Fatalf("building the request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Cookie", auth.SessionCookieName+"="+testToken)

	res, err := srv.Client().Do(req)
	if err != nil {
		t.Fatalf("POST: %v", err)
	}
	defer res.Body.Close()

	if res.StatusCode == http.StatusOK {
		t.Error("status = 200, want the request turned away without the protocol header")
	}
}

// The handler is what finally reads the account, so this pins the whole path:
// header, token, context, handler.
func TestNewHandsTheHandlerTheAuthenticatedAccount(t *testing.T) {
	srv := newTestServer(t, userIDHandler{})

	res, err := todoClient(srv.Client(), srv.URL).CreateTodo(
		t.Context(),
		connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"}),
	)
	if err != nil {
		t.Fatalf("CreateTodo() error = %v, want nil", err)
	}

	if got := res.Msg.GetTodo().GetId(); got != testUserID {
		t.Errorf("handler saw account %d, want %d", got, testUserID)
	}
}

// An Authorization header the interceptor cannot read a token out of is the
// same answer as no header at all, and the request never reaches the handler.
func TestNewRefusesARequestWithoutAUsableToken(t *testing.T) {
	tests := map[string]string{
		"no header":               "",
		"another scheme":          "Basic dXNlcjpwYXNz",
		"no scheme":               testToken,
		"the scheme alone":        "Bearer",
		"an empty token":          "Bearer    ",
		"a token nobody issued":   "Bearer not-the-token",
		"the token of a typo":     "Bearer " + testToken + "x",
		"the prefix run together": "Bearer" + testToken,
	}

	srv := newTestServer(t, panicOnCallHandler{t: t})

	for name, header := range tests {
		t.Run(name, func(t *testing.T) {
			client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

			req := connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"})
			if header != "" {
				req.Header().Set("Authorization", header)
			}

			_, err := client.CreateTodo(t.Context(), req)
			if got := connect.CodeOf(err); got != connect.CodeUnauthenticated {
				t.Errorf("CreateTodo() code = %v, want %v", got, connect.CodeUnauthenticated)
			}
		})
	}
}

// RFC 9110 makes the scheme case-insensitive, and clients do vary.
func TestNewAcceptsAnyCaseOfTheBearerScheme(t *testing.T) {
	srv := newTestServer(t, userIDHandler{})

	for _, scheme := range []string{"Bearer", "bearer", "BEARER", "BeArEr"} {
		t.Run(scheme, func(t *testing.T) {
			client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

			req := connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"})
			req.Header().Set("Authorization", scheme+" "+testToken)

			if _, err := client.CreateTodo(t.Context(), req); err != nil {
				t.Errorf("CreateTodo() error = %v, want nil", err)
			}
		})
	}
}

// AuthService is what hands out the tokens, so requiring one to reach it would
// leave no way in.
func TestNewServesAuthServiceWithoutAToken(t *testing.T) {
	srv := newTestServer(t, stubHandler{})

	client := authv1connect.NewAuthServiceClient(srv.Client(), srv.URL)

	res, err := client.LogIn(t.Context(), connect.NewRequest(&authv1.LogInRequest{
		Email:    "user@example.com",
		Password: "correct horse",
	}))
	if err != nil {
		t.Fatalf("LogIn() error = %v, want nil", err)
	}

	if diff := cmp.Diff(testToken, res.Msg.GetToken().GetAccessToken()); diff != "" {
		t.Errorf("LogIn() token (-want +got):\n%s", diff)
	}
}

// A rejected token must not buy the client a validation report of the message
// it sent, so the token is checked before the proto rules are.
func TestNewChecksTheTokenBeforeValidating(t *testing.T) {
	srv := newTestServer(t, panicOnCallHandler{t: t})

	client := todov1connect.NewTodoServiceClient(srv.Client(), srv.URL)

	_, err := client.CreateTodo(
		t.Context(),
		connect.NewRequest(&todov1.CreateTodoRequest{Title: "   "}),
	)
	if got := connect.CodeOf(err); got != connect.CodeUnauthenticated {
		t.Errorf("CreateTodo() code = %v, want %v", got, connect.CodeUnauthenticated)
	}
}

// The browser sends the token from a page on another origin, so the preflight
// has to allow the header or the request is never made.
func TestNewAllowsTheAuthorizationHeaderCrossOrigin(t *testing.T) {
	const origin = "http://localhost:8081"

	srv := newCORSTestServer(t, []string{origin}, stubHandler{})

	res := do(t, srv, http.MethodOptions, "/todo.v1.TodoService/CreateTodo", http.Header{
		"Origin":                         []string{origin},
		"Access-Control-Request-Method":  []string{http.MethodPost},
		"Access-Control-Request-Headers": []string{"authorization,connect-protocol-version,content-type"},
	})

	allowed := res.Header.Get("Access-Control-Allow-Headers")
	if !strings.Contains(strings.ToLower(allowed), "authorization") {
		t.Errorf("preflight Access-Control-Allow-Headers = %q, want it to contain %q", allowed, "authorization")
	}
}

// A lookup that could not be made says nothing about the token. Answered as a
// rejection, it would tell the client to log in again over a database failure
// its credentials have nothing to do with.
func TestNewReportsAFailedTokenLookupAsInternal(t *testing.T) {
	srv := serve(t, Deps{
		Todo:          panicOnCallHandler{t: t},
		Authenticator: stubAuthenticator{err: errors.New("the database is down")},
	})

	_, err := todoClient(srv.Client(), srv.URL).CreateTodo(
		t.Context(),
		connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"}),
	)
	if got := connect.CodeOf(err); got != connect.CodeInternal {
		t.Errorf("CreateTodo() code = %v, want %v", got, connect.CodeInternal)
	}
}
