package auth

import (
	"context"
	"errors"
	"net/http"
	"testing"
	"time"

	"connectrpc.com/connect"
	"github.com/google/go-cmp/cmp"

	"example/app/gen/db"
	authv1 "example/app/gen/go/auth/v1"
)

// sessionCookieOf finds the session cookie among the Set-Cookie headers of a
// response.
func sessionCookieOf(t *testing.T, header http.Header) *http.Cookie {
	t.Helper()

	res := http.Response{Header: header}
	for _, cookie := range res.Cookies() {
		if cookie.Name == SessionCookieName {
			return cookie
		}
	}

	t.Fatalf("no %q cookie among %v", SessionCookieName, header.Values("Set-Cookie"))

	return nil
}

// The whole point of the cookie is that a script on the page cannot read it,
// and that another site cannot make the browser send it.
func TestServiceSignUpSetsAnHTTPOnlySessionCookie(t *testing.T) {
	t.Parallel()

	issuer := newTestIssuer(t)
	svc := NewService(fakeQuerier{
		createUser: func(_ context.Context, arg db.CreateUserParams) (db.User, error) {
			return db.User{ID: 3, Email: arg.Email}, nil
		},
	}, issuer, false)

	res, err := svc.SignUp(t.Context(), connect.NewRequest(&authv1.SignUpRequest{
		Email:    testEmail,
		Password: testPassword,
	}))
	if err != nil {
		t.Fatalf("SignUp() error = %v, want nil", err)
	}

	cookie := sessionCookieOf(t, res.Header())

	if !cookie.HttpOnly {
		t.Error("cookie is readable by scripts, want HttpOnly")
	}
	if cookie.SameSite != http.SameSiteStrictMode {
		t.Errorf("cookie SameSite = %v, want %v", cookie.SameSite, http.SameSiteStrictMode)
	}
	if diff := cmp.Diff("/", cookie.Path); diff != "" {
		t.Errorf("cookie path (-want +got):\n%s", diff)
	}
	if cookie.MaxAge <= 0 {
		t.Errorf("cookie MaxAge = %d, want the session to last", cookie.MaxAge)
	}

	// It has to be a token the API will accept, and the same one the response
	// body carries for clients that send it themselves.
	userID, err := issuer.Verify(cookie.Value)
	if err != nil {
		t.Fatalf("Verify() on the cookie error = %v, want nil", err)
	}
	if userID != 3 {
		t.Errorf("cookie names account %d, want 3", userID)
	}
	if diff := cmp.Diff(res.Msg.GetToken().GetAccessToken(), cookie.Value); diff != "" {
		t.Errorf("cookie and response token differ (-body +cookie):\n%s", diff)
	}
}

func TestServiceLogInSetsTheSessionCookie(t *testing.T) {
	t.Parallel()

	issuer := newTestIssuer(t)
	svc := NewService(fakeQuerier{
		getUserByEmail: func(_ context.Context, email string) (db.User, error) {
			return db.User{ID: 3, Email: email, PasswordHash: hashOf(t, testPassword)}, nil
		},
	}, issuer, false)

	res, err := svc.LogIn(t.Context(), connect.NewRequest(&authv1.LogInRequest{
		Email:    testEmail,
		Password: testPassword,
	}))
	if err != nil {
		t.Fatalf("LogIn() error = %v, want nil", err)
	}

	if _, err := issuer.Verify(sessionCookieOf(t, res.Header()).Value); err != nil {
		t.Errorf("Verify() on the cookie error = %v, want nil", err)
	}
}

// A failed login must leave no session behind.
func TestServiceLogInSetsNoCookieOnFailure(t *testing.T) {
	t.Parallel()

	svc := newTestService(t, fakeQuerier{
		getUserByEmail: func(_ context.Context, email string) (db.User, error) {
			return db.User{ID: 3, Email: email, PasswordHash: hashOf(t, "another password")}, nil
		},
	})

	_, err := svc.LogIn(t.Context(), connect.NewRequest(&authv1.LogInRequest{
		Email:    testEmail,
		Password: testPassword,
	}))
	if err == nil {
		t.Fatal("LogIn() error = nil, want an error")
	}

	var connectErr *connect.Error
	if errors.As(err, &connectErr) {
		if got := connectErr.Meta().Values("Set-Cookie"); len(got) != 0 {
			t.Errorf("failed login set %v, want no cookie", got)
		}
	}
}

// A script cannot delete an HttpOnly cookie, so logging out is the server's
// job; what it sends has to match the original in everything but the lifetime,
// or the browser keeps two cookies instead of replacing one.
func TestServiceLogOutExpiresTheSessionCookie(t *testing.T) {
	t.Parallel()

	svc := newTestService(t, fakeQuerier{})

	res, err := svc.LogOut(t.Context(), connect.NewRequest(&authv1.LogOutRequest{}))
	if err != nil {
		t.Fatalf("LogOut() error = %v, want nil", err)
	}

	cookie := sessionCookieOf(t, res.Header())

	if cookie.MaxAge >= 0 {
		t.Errorf("cookie MaxAge = %d, want it negative so the browser drops it", cookie.MaxAge)
	}
	if diff := cmp.Diff("", cookie.Value); diff != "" {
		t.Errorf("cookie value (-want +got):\n%s", diff)
	}

	fresh := sessionCookie("a-token", time.Now().Add(time.Hour), false)
	if cookie.Path != fresh.Path || cookie.HttpOnly != fresh.HttpOnly ||
		cookie.Secure != fresh.Secure || cookie.SameSite != fresh.SameSite {
		t.Errorf("cleared cookie %+v does not match the one it replaces %+v", cookie, fresh)
	}
}

// Over https the cookie must not be offered on a plain http request.
func TestSessionCookieSecure(t *testing.T) {
	t.Parallel()

	if sessionCookie("a-token", time.Now().Add(time.Hour), false).Secure {
		t.Error("cookie is Secure with the flag off, which no http page could keep")
	}
	if !sessionCookie("a-token", time.Now().Add(time.Hour), true).Secure {
		t.Error("cookie is not Secure with the flag on")
	}
	if !clearedSessionCookie(true).Secure {
		t.Error("cleared cookie is not Secure with the flag on")
	}
}
