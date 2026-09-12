// Package integration exercises the queries and the services against a real
// Postgres, which is where the schema, the constraints and the SQLSTATE codes
// the services key on can be pinned. It is tests and nothing else.
package integration

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"connectrpc.com/connect"
	"github.com/google/go-cmp/cmp"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"example/app/gen/db"
	authv1 "example/app/gen/go/auth/v1"
	"example/app/internal/account"
	"example/app/internal/auth"
)

// schemaPath is api/schema.sql, the file the migrations are generated from,
// relative to this package.
const schemaPath = "../../schema.sql"

// cleanupTimeout bounds dropping the schema. It runs after the test's own
// context is cancelled, so it needs a deadline of its own.
const cleanupTimeout = 10 * time.Second

// newPool hands the test a pool pointed at a schema of its own, built from
// schema.sql and dropped afterwards. The database is the one the app uses; the
// schema is what keeps concurrent tests, and the app's own rows, out of each
// other's way.
func newPool(t *testing.T) *pgxpool.Pool {
	t.Helper()

	dbURL := os.Getenv("DB_URL")
	if dbURL == "" {
		t.Skip("DB_URL is not set: run these in the api container, where it is")
	}

	config, err := pgxpool.ParseConfig(dbURL)
	if err != nil {
		t.Fatalf("parsing DB_URL: %v", err)
	}

	var suffix [8]byte
	if _, err := rand.Read(suffix[:]); err != nil {
		t.Fatalf("naming the schema: %v", err)
	}
	schema := "test_" + hex.EncodeToString(suffix[:])
	quoted := pgx.Identifier{schema}.Sanitize()

	ctx := t.Context()

	admin, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		t.Fatalf("connecting to the database: %v", err)
	}
	defer admin.Close(ctx)

	if _, err := admin.Exec(ctx, "CREATE SCHEMA "+quoted); err != nil {
		t.Fatalf("creating the schema: %v", err)
	}
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), cleanupTimeout)
		defer cancel()

		conn, err := pgx.Connect(ctx, dbURL)
		if err != nil {
			t.Errorf("connecting to drop the schema: %v", err)

			return
		}
		defer conn.Close(ctx)

		if _, err := conn.Exec(ctx, "DROP SCHEMA "+quoted+" CASCADE"); err != nil {
			t.Errorf("dropping the schema: %v", err)
		}
	})

	statements, err := os.ReadFile(schemaPath)
	if err != nil {
		t.Fatalf("reading %s: %v", schemaPath, err)
	}
	if _, err := admin.Exec(ctx, "SET search_path TO "+quoted); err != nil {
		t.Fatalf("selecting the schema: %v", err)
	}
	if _, err := admin.Exec(ctx, string(statements)); err != nil {
		t.Fatalf("applying %s: %v", schemaPath, err)
	}

	// Every pooled connection lands in the same schema, which is what makes
	// the unqualified table names in the generated queries resolve to it.
	config.ConnConfig.RuntimeParams["search_path"] = schema

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		t.Fatalf("opening the pool: %v", err)
	}
	t.Cleanup(pool.Close)

	return pool
}

func newQueries(t *testing.T) *db.Queries {
	t.Helper()

	return db.New(newPool(t))
}

// createUser inserts an account straight through the queries, skipping the
// hashing the service would do: what is under test here is the table.
func createUser(t *testing.T, queries *db.Queries, email string) db.User {
	t.Helper()

	user, err := queries.CreateUser(t.Context(), db.CreateUserParams{
		Email:        email,
		PasswordHash: "not a real hash",
	})
	if err != nil {
		t.Fatalf("CreateUser(%q): %v", email, err)
	}

	return user
}

func createTodo(t *testing.T, queries *db.Queries, userID int64, title string) db.Todo {
	t.Helper()

	todo, err := queries.CreateTodo(t.Context(), db.CreateTodoParams{UserID: userID, Title: title})
	if err != nil {
		t.Fatalf("CreateTodo(%q): %v", title, err)
	}

	return todo
}

// The scoping the queries promise is only real if the database enforces it, so
// it is checked against one.
func TestTodosAreScopedToTheirOwner(t *testing.T) {
	queries := newQueries(t)
	ctx := t.Context()

	alice := createUser(t, queries, "alice@example.com")
	bob := createUser(t, queries, "bob@example.com")

	aliceTodo := createTodo(t, queries, alice.ID, "alice's todo")
	createTodo(t, queries, bob.ID, "bob's todo")

	rows, err := queries.ListTodos(ctx, db.ListTodosParams{UserID: bob.ID, PageSize: 10})
	if err != nil {
		t.Fatalf("ListTodos(): %v", err)
	}
	if len(rows) != 1 || rows[0].Title != "bob's todo" {
		t.Errorf("ListTodos() for bob = %v, want only his own todo", rows)
	}

	// Bob naming Alice's id gets the same answer as naming one that does not
	// exist, so the API can report both as not found.
	_, err = queries.UpdateTodo(ctx, db.UpdateTodoParams{ID: aliceTodo.ID, UserID: bob.ID})
	if !errors.Is(err, pgx.ErrNoRows) {
		t.Errorf("UpdateTodo() of another user's todo error = %v, want %v", err, pgx.ErrNoRows)
	}

	deleted, err := queries.DeleteTodo(ctx, db.DeleteTodoParams{ID: aliceTodo.ID, UserID: bob.ID})
	if err != nil {
		t.Fatalf("DeleteTodo(): %v", err)
	}
	if deleted != 0 {
		t.Errorf("DeleteTodo() of another user's todo deleted %d rows, want 0", deleted)
	}

	// And it really is untouched.
	still, err := queries.ListTodos(ctx, db.ListTodosParams{UserID: alice.ID, PageSize: 10})
	if err != nil {
		t.Fatalf("ListTodos(): %v", err)
	}
	if len(still) != 1 {
		t.Errorf("alice has %d todos, want 1", len(still))
	}
}

// The service asks for one row more than the page to learn whether a further
// page exists; walking the tokens has to visit every todo exactly once.
func TestListTodosWalksEveryTodoOnce(t *testing.T) {
	queries := newQueries(t)
	ctx := t.Context()

	user := createUser(t, queries, "walker@example.com")

	var want []string
	for _, title := range []string{"one", "two", "three", "four", "five"} {
		createTodo(t, queries, user.ID, title)
		want = append(want, title)
	}

	var got []string
	after := int64(0)
	for {
		rows, err := queries.ListTodos(ctx, db.ListTodosParams{
			UserID:   user.ID,
			AfterID:  after,
			PageSize: 2,
		})
		if err != nil {
			t.Fatalf("ListTodos(): %v", err)
		}
		if len(rows) == 0 {
			break
		}

		for _, row := range rows {
			got = append(got, row.Title)
		}
		after = rows[len(rows)-1].ID
	}

	if diff := cmp.Diff(want, got); diff != "" {
		t.Errorf("titles walked (-want +got):\n%s", diff)
	}
}

// The check constraint is the backstop behind the API's own title rules, so it
// is worth knowing it is actually there.
func TestTodoTitleCheckConstraint(t *testing.T) {
	queries := newQueries(t)

	user := createUser(t, queries, "titles@example.com")

	tests := map[string]string{
		"blank":                    "   ",
		"past the 1000 rune limit": strings.Repeat("a", 1001),
	}

	for name, title := range tests {
		t.Run(name, func(t *testing.T) {
			_, err := queries.CreateTodo(t.Context(), db.CreateTodoParams{
				UserID: user.ID,
				Title:  title,
			})
			if err == nil {
				t.Fatal("CreateTodo() error = nil, want the check constraint to refuse it")
			}
		})
	}
}

// The sign-up path reports a taken address by reading this code off the
// failed insert (api/internal/auth/service.go), so the code has to be right.
func TestDuplicateEmailRaisesAUniqueViolation(t *testing.T) {
	queries := newQueries(t)

	createUser(t, queries, "twice@example.com")

	_, err := queries.CreateUser(t.Context(), db.CreateUserParams{
		Email:        "twice@example.com",
		PasswordHash: "not a real hash",
	})

	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		t.Fatalf("CreateUser() error = %v, want a *pgconn.PgError", err)
	}
	if pgErr.Code != "23505" {
		t.Errorf("CreateUser() SQLSTATE = %s, want 23505", pgErr.Code)
	}
}

func TestDeletingAUserTakesTheirTodos(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)
	ctx := t.Context()

	user := createUser(t, queries, "leaving@example.com")
	createTodo(t, queries, user.ID, "will go with the account")

	if _, err := pool.Exec(ctx, "DELETE FROM users WHERE id = $1", user.ID); err != nil {
		t.Fatalf("deleting the user: %v", err)
	}

	var remaining int
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM todos").Scan(&remaining); err != nil {
		t.Fatalf("counting the todos: %v", err)
	}
	if remaining != 0 {
		t.Errorf("%d todos survived the account, want 0", remaining)
	}
}

// openSession writes the row a token names, the way SignUp and LogIn do, and
// returns a token for it.
func openSession(t *testing.T, queries *db.Queries, issuer *auth.Issuer, userID int64) (string, db.Session) {
	t.Helper()

	now := time.Now()
	expiresAt := issuer.Expiry(now)

	session, err := queries.CreateSession(t.Context(), db.CreateSessionParams{
		UserID:    userID,
		ExpiresAt: pgtype.Timestamptz{Time: expiresAt, Valid: true},
	})
	if err != nil {
		t.Fatalf("CreateSession(): %v", err)
	}

	token, err := issuer.Issue(userID, session.ID, now, expiresAt)
	if err != nil {
		t.Fatalf("Issue(): %v", err)
	}

	return token, session
}

// The token of a deleted account stays signed and unexpired, so what settles
// it is the session row, which the account's deletion cascades away.
func TestTokensOfADeletedUserStopVerifying(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)
	ctx := t.Context()

	issuer, err := auth.NewIssuer("token-secret-for-tests-only-0123")
	if err != nil {
		t.Fatalf("NewIssuer(): %v", err)
	}
	verifier := auth.NewVerifier(issuer, queries)

	user := createUser(t, queries, "leaving@example.com")
	token, _ := openSession(t, queries, issuer, user.ID)

	if _, err := verifier.Verify(ctx, token); err != nil {
		t.Fatalf("Verify() before the deletion: error = %v, want nil", err)
	}

	if _, err := pool.Exec(ctx, "DELETE FROM users WHERE id = $1", user.ID); err != nil {
		t.Fatalf("deleting the user: %v", err)
	}

	if _, err := verifier.Verify(ctx, token); !errors.Is(err, auth.ErrRejected) {
		t.Errorf("Verify() after the deletion: error = %v, want one matching ErrRejected", err)
	}
}

// Logging out is the whole reason the rows exist: the token stays signed and
// unexpired afterwards, and has to stop being served anyway.
func TestLogOutStopsTheTokenItWasGiven(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)
	ctx := t.Context()

	issuer, err := auth.NewIssuer("token-secret-for-tests-only-0123")
	if err != nil {
		t.Fatalf("NewIssuer(): %v", err)
	}

	authService := auth.NewService(queries, issuer, false)
	verifier := auth.NewVerifier(issuer, queries)

	res, err := authService.SignUp(ctx, connect.NewRequest(&authv1.SignUpRequest{
		Email:    "logsout@example.com",
		Password: "correct horse",
	}))
	if err != nil {
		t.Fatalf("SignUp(): %v", err)
	}

	token := res.Msg.GetToken().GetAccessToken()
	if _, err := verifier.Verify(ctx, token); err != nil {
		t.Fatalf("Verify() before the log out: error = %v, want nil", err)
	}

	req := connect.NewRequest(&authv1.LogOutRequest{})
	req.Header().Set("Authorization", "Bearer "+token)

	if _, err := authService.LogOut(ctx, req); err != nil {
		t.Fatalf("LogOut(): %v", err)
	}

	if _, err := verifier.Verify(ctx, token); !errors.Is(err, auth.ErrRejected) {
		t.Errorf("Verify() after the log out: error = %v, want one matching ErrRejected", err)
	}
}

// Only the session that logged out ends. The other devices an account is
// signed in on carry tokens of their own, and none of them is what was closed.
func TestLogOutLeavesTheAccountsOtherSessions(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)
	ctx := t.Context()

	issuer, err := auth.NewIssuer("token-secret-for-tests-only-0123")
	if err != nil {
		t.Fatalf("NewIssuer(): %v", err)
	}

	authService := auth.NewService(queries, issuer, false)
	verifier := auth.NewVerifier(issuer, queries)

	user := createUser(t, queries, "twodevices@example.com")
	first, _ := openSession(t, queries, issuer, user.ID)
	second, _ := openSession(t, queries, issuer, user.ID)

	req := connect.NewRequest(&authv1.LogOutRequest{})
	req.Header().Set("Authorization", "Bearer "+first)

	if _, err := authService.LogOut(ctx, req); err != nil {
		t.Fatalf("LogOut(): %v", err)
	}

	if _, err := verifier.Verify(ctx, first); !errors.Is(err, auth.ErrRejected) {
		t.Errorf("Verify() on the session that logged out: error = %v, want one matching ErrRejected", err)
	}
	if _, err := verifier.Verify(ctx, second); err != nil {
		t.Errorf("Verify() on the other session: error = %v, want nil", err)
	}
}

// A token has to name the session it was issued with: pairing a session with
// another account's id is what the two-column lookup is there to catch.
func TestASessionOnlyServesTheAccountItWasOpenedFor(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)

	issuer, err := auth.NewIssuer("token-secret-for-tests-only-0123")
	if err != nil {
		t.Fatalf("NewIssuer(): %v", err)
	}
	verifier := auth.NewVerifier(issuer, queries)

	owner := createUser(t, queries, "owns-the-session@example.com")
	other := createUser(t, queries, "wants-it@example.com")

	_, session := openSession(t, queries, issuer, owner.ID)

	now := time.Now()
	borrowed, err := issuer.Issue(other.ID, session.ID, now, issuer.Expiry(now))
	if err != nil {
		t.Fatalf("Issue(): %v", err)
	}

	if _, err := verifier.Verify(t.Context(), borrowed); !errors.Is(err, auth.ErrRejected) {
		t.Errorf("Verify() on a borrowed session: error = %v, want one matching ErrRejected", err)
	}
}

// Closing a session names the account too (api/queries/sessions.sql). LogOut
// takes both out of one verified token and so cannot hand over a mismatched
// pair, which is why the condition is pinned at the query rather than through
// the service.
func TestDeletingASessionOfAnotherAccountLeavesItOpen(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)
	ctx := t.Context()

	issuer, err := auth.NewIssuer("token-secret-for-tests-only-0123")
	if err != nil {
		t.Fatalf("NewIssuer(): %v", err)
	}
	verifier := auth.NewVerifier(issuer, queries)

	owner := createUser(t, queries, "keeps-the-session@example.com")
	other := createUser(t, queries, "reaches-for-it@example.com")

	token, session := openSession(t, queries, issuer, owner.ID)

	if err := queries.DeleteSession(ctx, db.DeleteSessionParams{
		ID:     session.ID,
		UserID: other.ID,
	}); err != nil {
		t.Fatalf("DeleteSession(): %v", err)
	}
	if _, err := verifier.Verify(ctx, token); err != nil {
		t.Errorf("Verify() after another account named the session: error = %v, want nil", err)
	}

	// The owner still closes it, so what the condition refuses is the pair and
	// not the id.
	if err := queries.DeleteSession(ctx, db.DeleteSessionParams{
		ID:     session.ID,
		UserID: owner.ID,
	}); err != nil {
		t.Fatalf("DeleteSession(): %v", err)
	}
	if _, err := verifier.Verify(ctx, token); !errors.Is(err, auth.ErrRejected) {
		t.Errorf("Verify() after the owner closed the session: error = %v, want one matching ErrRejected", err)
	}
}

// Nothing sweeps the table on a schedule, so opening a session is what drops
// the account's finished ones (api/queries/sessions.sql).
func TestOpeningASessionSweepsTheAccountsExpiredOnes(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)
	ctx := t.Context()

	user := createUser(t, queries, "sweeps@example.com")

	expired, err := queries.CreateSession(ctx, db.CreateSessionParams{
		UserID:    user.ID,
		ExpiresAt: pgtype.Timestamptz{Time: time.Now().Add(-time.Hour), Valid: true},
	})
	if err != nil {
		t.Fatalf("CreateSession(): %v", err)
	}

	fresh, err := queries.CreateSession(ctx, db.CreateSessionParams{
		UserID:    user.ID,
		ExpiresAt: pgtype.Timestamptz{Time: time.Now().Add(time.Hour), Valid: true},
	})
	if err != nil {
		t.Fatalf("CreateSession(): %v", err)
	}

	gone, err := queries.SessionExists(ctx, db.SessionExistsParams{ID: expired.ID, UserID: user.ID})
	if err != nil {
		t.Fatalf("SessionExists(): %v", err)
	}
	if gone {
		t.Error("the expired session survived, want it swept")
	}

	kept, err := queries.SessionExists(ctx, db.SessionExistsParams{ID: fresh.ID, UserID: user.ID})
	if err != nil {
		t.Fatalf("SessionExists(): %v", err)
	}
	if !kept {
		t.Error("the session that was just opened is gone")
	}
}

// Signing up, then working as the account the token names, is the path a
// client actually takes; here it runs against the real tables.
func TestSignUpThenOwnTodos(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)
	ctx := t.Context()

	issuer, err := auth.NewIssuer("token-secret-for-tests-only-0123")
	if err != nil {
		t.Fatalf("NewIssuer(): %v", err)
	}

	authService := auth.NewService(queries, issuer, false)

	credentials := authv1.SignUpRequest{Email: "owner@example.com", Password: "correct horse"}

	res, err := authService.SignUp(ctx, connect.NewRequest(&credentials))
	if err != nil {
		t.Fatalf("SignUp(): %v", err)
	}

	userID, _, err := issuer.Verify(res.Msg.GetToken().GetAccessToken())
	if err != nil {
		t.Fatalf("Verify(): %v", err)
	}

	todo := createTodo(t, queries, userID, "buy milk")
	if todo.UserID != userID {
		t.Errorf("todo belongs to %d, want %d", todo.UserID, userID)
	}

	// The same credentials come back to the same account.
	logIn, err := authService.LogIn(ctx, connect.NewRequest(&authv1.LogInRequest{
		Email:    credentials.GetEmail(),
		Password: credentials.GetPassword(),
	}))
	if err != nil {
		t.Fatalf("LogIn(): %v", err)
	}
	loggedInID, _, err := issuer.Verify(logIn.Msg.GetToken().GetAccessToken())
	if err != nil {
		t.Fatalf("Verify(): %v", err)
	}
	if loggedInID != userID {
		t.Errorf("LogIn() names account %d, want %d", loggedInID, userID)
	}
}

// countClosed reports how many rows the account still has, closed or not, by
// going around the queries: every one of them filters deleted_at, which is
// exactly what these tests need to see past.
func countClosed(t *testing.T, pool *pgxpool.Pool, userID int64) int {
	t.Helper()

	var count int
	if err := pool.QueryRow(t.Context(),
		"SELECT count(*) FROM users WHERE id = $1 AND deleted_at IS NOT NULL", userID,
	).Scan(&count); err != nil {
		t.Fatalf("counting the closed rows of account %d: %v", userID, err)
	}

	return count
}

// Closing an account is the whole point of deleted_at: the row stays, and
// everything that reads it has to stop finding it anyway.
func TestClosingAnAccountEndsEverySessionItHas(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)
	ctx := t.Context()

	issuer, err := auth.NewIssuer("token-secret-for-tests-only-0123")
	if err != nil {
		t.Fatalf("NewIssuer(): %v", err)
	}
	verifier := auth.NewVerifier(issuer, queries)

	user := createUser(t, queries, "closing@example.com")
	phone, _ := openSession(t, queries, issuer, user.ID)
	laptop, _ := openSession(t, queries, issuer, user.ID)

	if _, err := verifier.Verify(ctx, phone); err != nil {
		t.Fatalf("Verify() before the closing: error = %v, want nil", err)
	}

	closed, err := queries.CloseAccount(ctx, user.ID)
	if err != nil {
		t.Fatalf("CloseAccount(): %v", err)
	}
	if !closed.DeletedAt.Valid {
		t.Fatal("the closed row carries no instant")
	}

	// Both of them, not only the one that asked: there is no account left for
	// either to act as.
	for name, token := range map[string]string{"phone": phone, "laptop": laptop} {
		if _, err := verifier.Verify(ctx, token); !errors.Is(err, auth.ErrRejected) {
			t.Errorf("Verify() on the %s: error = %v, want one matching ErrRejected", name, err)
		}
	}

	// The row survives, which is what the grace period is: a purge finds it
	// later, and until then an operator can put deleted_at back to null.
	if got := countClosed(t, pool, user.ID); got != 1 {
		t.Errorf("closed rows = %d, want 1", got)
	}
}

// The session lookup reads the account as well, so a session that outlives the
// closing serves nothing. Nothing should leave one behind, the closing taking
// them in the same statement; this is the backstop for when something does
// (api/queries/sessions.sql).
func TestASessionThatOutlivesTheClosingServesNothing(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)
	ctx := t.Context()

	issuer, err := auth.NewIssuer("token-secret-for-tests-only-0123")
	if err != nil {
		t.Fatalf("NewIssuer(): %v", err)
	}
	verifier := auth.NewVerifier(issuer, queries)

	user := createUser(t, queries, "leftover@example.com")

	if _, err := queries.CloseAccount(ctx, user.ID); err != nil {
		t.Fatalf("CloseAccount(): %v", err)
	}

	// Opened after the closing, which is the only way to have one: it is the
	// same row a session that survived the closing would leave.
	token, _ := openSession(t, queries, issuer, user.ID)

	if _, err := verifier.Verify(ctx, token); !errors.Is(err, auth.ErrRejected) {
		t.Errorf("Verify() error = %v, want one matching ErrRejected", err)
	}
}

// A closed account cannot be logged back in to, which is why the grace period
// is an operator's window rather than the owner's.
func TestAClosedAccountCannotLogIn(t *testing.T) {
	queries := newQueries(t)
	ctx := t.Context()

	issuer, err := auth.NewIssuer("token-secret-for-tests-only-0123")
	if err != nil {
		t.Fatalf("NewIssuer(): %v", err)
	}
	authService := auth.NewService(queries, issuer, false)

	const email, password = "shutsthedoor@example.com", "correct horse"

	signUp, err := authService.SignUp(ctx, connect.NewRequest(&authv1.SignUpRequest{
		Email:    email,
		Password: password,
	}))
	if err != nil {
		t.Fatalf("SignUp(): %v", err)
	}

	userID, _, err := issuer.Verify(signUp.Msg.GetToken().GetAccessToken())
	if err != nil {
		t.Fatalf("Verify(): %v", err)
	}

	if _, err := queries.CloseAccount(ctx, userID); err != nil {
		t.Fatalf("CloseAccount(): %v", err)
	}

	_, err = authService.LogIn(ctx, connect.NewRequest(&authv1.LogInRequest{
		Email:    email,
		Password: password,
	}))
	// The same answer a wrong password gets, the password here being right:
	// which of the two it was is not something the API says.
	if got := connect.CodeOf(err); got != connect.CodeUnauthenticated {
		t.Errorf("LogIn() code = %v, want %v", got, connect.CodeUnauthenticated)
	}
}

// The address stays with the closed account until the purge erases the row, so
// that an account closed by mistake always has somewhere to be restored to
// (api/schema.sql). Nobody can take it in the meantime.
func TestTheAddressOfAClosedAccountIsHeldUntilThePurge(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)
	ctx := t.Context()

	issuer, err := auth.NewIssuer("token-secret-for-tests-only-0123")
	if err != nil {
		t.Fatalf("NewIssuer(): %v", err)
	}
	authService := auth.NewService(queries, issuer, false)

	const email = "comesback@example.com"

	first := createUser(t, queries, email)
	if _, err := queries.CloseAccount(ctx, first.ID); err != nil {
		t.Fatalf("CloseAccount(): %v", err)
	}

	// The closed row answers no login, the lookup passing over it...
	if _, err := queries.GetUserByEmail(ctx, email); !errors.Is(err, pgx.ErrNoRows) {
		t.Errorf("GetUserByEmail() on the closed account: error = %v, want %v", err, pgx.ErrNoRows)
	}

	// ...and still holds the address against a new account.
	_, err = authService.SignUp(ctx, connect.NewRequest(&authv1.SignUpRequest{
		Email:    email,
		Password: "a different password",
	}))
	if got := connect.CodeOf(err); got != connect.CodeAlreadyExists {
		t.Fatalf("SignUp() during the grace period: code = %v, want %v", got, connect.CodeAlreadyExists)
	}

	// Erasing the row is what frees the address. Backdated rather than waited
	// out, as in TestPurgeErasesOnlyTheAccountsPastTheGracePeriod.
	if _, err := pool.Exec(ctx,
		"UPDATE users SET deleted_at = now() - $1::interval WHERE id = $2",
		(account.GracePeriod + time.Hour).String(), first.ID,
	); err != nil {
		t.Fatalf("backdating the closing: %v", err)
	}
	if _, err := account.Purge(ctx, queries, time.Now()); err != nil {
		t.Fatalf("Purge(): %v", err)
	}

	again, err := authService.SignUp(ctx, connect.NewRequest(&authv1.SignUpRequest{
		Email:    email,
		Password: "a different password",
	}))
	if err != nil {
		t.Fatalf("SignUp() after the purge: error = %v, want nil", err)
	}

	// A new account rather than the old one back.
	secondID, _, err := issuer.Verify(again.Msg.GetToken().GetAccessToken())
	if err != nil {
		t.Fatalf("Verify(): %v", err)
	}
	if secondID == first.ID {
		t.Error("SignUp() reopened the closed account, want a new one")
	}
}

// What the purge erases is the accounts whose grace period is up, and nothing
// else. An open account and one closed a moment ago are both left alone.
func TestPurgeErasesOnlyTheAccountsPastTheGracePeriod(t *testing.T) {
	pool := newPool(t)
	queries := db.New(pool)
	ctx := t.Context()

	open := createUser(t, queries, "stays@example.com")
	recent := createUser(t, queries, "justleft@example.com")
	old := createUser(t, queries, "longgone@example.com")

	createTodo(t, queries, old.ID, "goes with the account")

	for _, user := range []db.User{recent, old} {
		if _, err := queries.CloseAccount(ctx, user.ID); err != nil {
			t.Fatalf("CloseAccount(%d): %v", user.ID, err)
		}
	}

	// Backdated rather than waited out: the grace period is a month, and the
	// column is what the purge reads.
	if _, err := pool.Exec(ctx,
		"UPDATE users SET deleted_at = now() - $1::interval WHERE id = $2",
		(account.GracePeriod + time.Hour).String(), old.ID,
	); err != nil {
		t.Fatalf("backdating the closing: %v", err)
	}

	erased, err := account.Purge(ctx, queries, time.Now())
	if err != nil {
		t.Fatalf("Purge(): %v", err)
	}
	if erased != 1 {
		t.Errorf("Purge() erased %d accounts, want 1", erased)
	}

	if got := countClosed(t, pool, old.ID); got != 0 {
		t.Errorf("the account past its grace period has %d rows left, want 0", got)
	}
	if got := countClosed(t, pool, recent.ID); got != 1 {
		t.Errorf("the account just closed has %d rows, want 1", got)
	}
	if _, err := queries.GetUserByID(ctx, open.ID); err != nil {
		t.Errorf("GetUserByID() on the open account: error = %v, want nil", err)
	}

	// The todos go through the foreign key, which is what makes the purge the
	// erasure the answer to DeleteAccount promised.
	todos, err := queries.ListTodos(ctx, db.ListTodosParams{UserID: old.ID, PageSize: 10})
	if err != nil {
		t.Fatalf("ListTodos(): %v", err)
	}
	if len(todos) != 0 {
		t.Errorf("the erased account still has %d todos, want 0", len(todos))
	}
}
