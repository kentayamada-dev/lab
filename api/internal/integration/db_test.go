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
	"github.com/jackc/pgx/v5/pgxpool"

	"example/app/gen/db"
	authv1 "example/app/gen/go/auth/v1"
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

// The token of a deleted account stays signed and unexpired, so what settles
// it is the lookup the verifier makes against the table the row went from.
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

	token, _, err := issuer.Issue(user.ID, time.Now())
	if err != nil {
		t.Fatalf("Issue(): %v", err)
	}

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

	userID, err := issuer.Verify(res.Msg.GetToken().GetAccessToken())
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
	loggedInID, err := issuer.Verify(logIn.Msg.GetToken().GetAccessToken())
	if err != nil {
		t.Fatalf("Verify(): %v", err)
	}
	if loggedInID != userID {
		t.Errorf("LogIn() names account %d, want %d", loggedInID, userID)
	}
}
