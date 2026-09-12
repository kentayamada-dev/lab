package account

import (
	"context"
	"errors"
	"net/http"
	"testing"
	"time"

	"connectrpc.com/connect"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/crypto/bcrypt"

	"example/app/gen/db"
	accountv1 "example/app/gen/go/account/v1"
	"example/app/internal/auth"
)

const (
	testUserID   int64 = 3
	testPassword       = "correct horse"
)

var errQuery = errors.New("query failed")

// testHash is the stored hash of testPassword. Computed once because bcrypt is
// deliberately slow and every test here needs the same one.
func testHash(t *testing.T) string {
	t.Helper()

	hash, err := bcrypt.GenerateFromPassword([]byte(testPassword), bcrypt.MinCost)
	if err != nil {
		t.Fatalf("GenerateFromPassword(): %v", err)
	}

	return string(hash)
}

type fakeQuerier struct {
	getUserByID  func(ctx context.Context, id int64) (db.User, error)
	closeAccount func(ctx context.Context, id int64) (db.CloseAccountRow, error)
}

func (f fakeQuerier) GetUserByID(ctx context.Context, id int64) (db.User, error) {
	return f.getUserByID(ctx, id)
}

// Standing in for itself when a test leaves it out: most of what is under test
// here happens before the account is closed, and the row that comes back only
// has to carry an instant.
func (f fakeQuerier) CloseAccount(ctx context.Context, id int64) (db.CloseAccountRow, error) {
	if f.closeAccount == nil {
		return db.CloseAccountRow{
			ID:        id,
			DeletedAt: pgtype.Timestamptz{Time: time.Now(), Valid: true},
		}, nil
	}

	return f.closeAccount(ctx, id)
}

var _ Querier = fakeQuerier{}

// openAccount is a querier that finds the account and takes testPassword.
func openAccount(t *testing.T) fakeQuerier {
	t.Helper()

	hash := testHash(t)

	return fakeQuerier{
		getUserByID: func(_ context.Context, id int64) (db.User, error) {
			return db.User{ID: id, PasswordHash: hash}, nil
		},
	}
}

// authenticated is the context the interceptor hands a handler
// (api/internal/server/auth.go).
func authenticated(t *testing.T) context.Context {
	t.Helper()

	return auth.ContextWithUserID(t.Context(), testUserID)
}

func deleteRequest(password string) *connect.Request[accountv1.DeleteAccountRequest] {
	return connect.NewRequest(&accountv1.DeleteAccountRequest{Password: password})
}

// The account closed is the one the token named, and the response says when it
// stops existing so a client can tell the reader.
func TestDeleteAccountClosesTheAuthenticatedAccount(t *testing.T) {
	t.Parallel()

	closedAt := time.Now()
	closed := int64(0)

	queries := openAccount(t)
	queries.closeAccount = func(_ context.Context, id int64) (db.CloseAccountRow, error) {
		closed = id

		return db.CloseAccountRow{
			ID:        id,
			DeletedAt: pgtype.Timestamptz{Time: closedAt, Valid: true},
		}, nil
	}

	res, err := NewService(queries, false).DeleteAccount(authenticated(t), deleteRequest(testPassword))
	if err != nil {
		t.Fatalf("DeleteAccount() error = %v, want nil", err)
	}

	if closed != testUserID {
		t.Errorf("closed account %d, want %d", closed, testUserID)
	}
	if want := PurgeAt(closedAt); !res.Msg.GetPurgeAt().AsTime().Equal(want) {
		t.Errorf("purge_at = %v, want %v", res.Msg.GetPurgeAt().AsTime(), want)
	}
}

// The sessions are gone with the account, so the browser is left holding a
// cookie for one that no longer exists and cannot clear it itself.
func TestDeleteAccountClearsTheSessionCookie(t *testing.T) {
	t.Parallel()

	res, err := NewService(openAccount(t), false).
		DeleteAccount(authenticated(t), deleteRequest(testPassword))
	if err != nil {
		t.Fatalf("DeleteAccount() error = %v, want nil", err)
	}

	cookies := (&http.Response{Header: res.Header()}).Cookies()
	if len(cookies) != 1 {
		t.Fatalf("response set %d cookies, want 1", len(cookies))
	}
	if got := cookies[0]; got.Name != auth.SessionCookieName || got.Value != "" || got.MaxAge >= 0 {
		t.Errorf("cookie = %+v, want the session cookie expired", got)
	}
}

// The session alone reaches the procedure; the password is what runs it.
func TestDeleteAccountRefusesAWrongPassword(t *testing.T) {
	t.Parallel()

	queries := openAccount(t)
	queries.closeAccount = func(context.Context, int64) (db.CloseAccountRow, error) {
		t.Error("CloseAccount called, want the password checked first")

		return db.CloseAccountRow{}, nil
	}

	_, err := NewService(queries, false).
		DeleteAccount(authenticated(t), deleteRequest("not the password"))
	if got := connect.CodeOf(err); got != connect.CodeUnauthenticated {
		t.Errorf("DeleteAccount() code = %v, want %v", got, connect.CodeUnauthenticated)
	}
}

// Reaching the handler without the interceptor having resolved an account is a
// wiring mistake, and the safe answer to it is the one a missing token gets.
func TestDeleteAccountWithoutAnAccountOnTheContext(t *testing.T) {
	t.Parallel()

	queries := fakeQuerier{
		getUserByID: func(context.Context, int64) (db.User, error) {
			t.Error("GetUserByID called, want the request turned away first")

			return db.User{}, nil
		},
	}

	_, err := NewService(queries, false).DeleteAccount(t.Context(), deleteRequest(testPassword))
	if got := connect.CodeOf(err); got != connect.CodeUnauthenticated {
		t.Errorf("DeleteAccount() code = %v, want %v", got, connect.CodeUnauthenticated)
	}
}

// Two requests closing the same account race; the one that loses finds nothing
// left to close.
func TestDeleteAccountOnAnAccountThatIsAlreadyClosed(t *testing.T) {
	t.Parallel()

	tests := map[string]fakeQuerier{
		"gone before the password is read": {
			getUserByID: func(context.Context, int64) (db.User, error) {
				return db.User{}, pgx.ErrNoRows
			},
		},
		"gone between reading it and closing": {
			closeAccount: func(context.Context, int64) (db.CloseAccountRow, error) {
				return db.CloseAccountRow{}, pgx.ErrNoRows
			},
		},
	}

	hash := testHash(t)

	for name, queries := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			if queries.getUserByID == nil {
				queries.getUserByID = func(_ context.Context, id int64) (db.User, error) {
					return db.User{ID: id, PasswordHash: hash}, nil
				}
			}

			_, err := NewService(queries, false).
				DeleteAccount(authenticated(t), deleteRequest(testPassword))
			if got := connect.CodeOf(err); got != connect.CodeUnauthenticated {
				t.Errorf("DeleteAccount() code = %v, want %v", got, connect.CodeUnauthenticated)
			}
		})
	}
}

// A failure to find out is the server's fault, not an answer about the
// account.
func TestDeleteAccountReportsAFailedQuery(t *testing.T) {
	t.Parallel()

	hash := testHash(t)

	tests := map[string]fakeQuerier{
		"looking the account up": {
			getUserByID: func(context.Context, int64) (db.User, error) {
				return db.User{}, errQuery
			},
		},
		"closing it": {
			getUserByID: func(_ context.Context, id int64) (db.User, error) {
				return db.User{ID: id, PasswordHash: hash}, nil
			},
			closeAccount: func(context.Context, int64) (db.CloseAccountRow, error) {
				return db.CloseAccountRow{}, errQuery
			},
		},
		// Nothing can compute the purge instant from this, and answering with
		// a made up one would be a promise the row does not carry.
		"closing it without recording when": {
			getUserByID: func(_ context.Context, id int64) (db.User, error) {
				return db.User{ID: id, PasswordHash: hash}, nil
			},
			closeAccount: func(_ context.Context, id int64) (db.CloseAccountRow, error) {
				return db.CloseAccountRow{ID: id}, nil
			},
		},
	}

	for name, queries := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			res, err := NewService(queries, false).
				DeleteAccount(authenticated(t), deleteRequest(testPassword))
			if got := connect.CodeOf(err); got != connect.CodeInternal {
				t.Errorf("DeleteAccount() code = %v, want %v", got, connect.CodeInternal)
			}
			if res != nil {
				t.Error("DeleteAccount() returned a response alongside the error")
			}
		})
	}
}

// The cookie being cleared has to match the one that was set, or the browser
// keeps both (api/internal/auth/cookie.go).
func TestDeleteAccountClearsTheCookieTheWayItWasIssued(t *testing.T) {
	t.Parallel()

	for _, secure := range []bool{false, true} {
		res, err := NewService(openAccount(t), secure).
			DeleteAccount(authenticated(t), deleteRequest(testPassword))
		if err != nil {
			t.Fatalf("DeleteAccount() error = %v, want nil", err)
		}

		cookies := (&http.Response{Header: res.Header()}).Cookies()
		if len(cookies) != 1 || cookies[0].Secure != secure {
			t.Errorf("cookie Secure = %v, want %v", cookies, secure)
		}
	}
}
