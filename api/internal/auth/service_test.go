package auth

import (
	"context"
	"errors"
	"testing"

	"connectrpc.com/connect"
	"github.com/google/go-cmp/cmp"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"golang.org/x/crypto/bcrypt"

	"example/app/gen/db"
	authv1 "example/app/gen/go/auth/v1"
)

const (
	testEmail    = "user@example.com"
	testPassword = "correct horse"
)

var errQuery = errors.New("query failed")

type fakeQuerier struct {
	createUser     func(ctx context.Context, arg db.CreateUserParams) (db.User, error)
	getUserByEmail func(ctx context.Context, email string) (db.User, error)
}

func (f fakeQuerier) CreateUser(ctx context.Context, arg db.CreateUserParams) (db.User, error) {
	return f.createUser(ctx, arg)
}

func (f fakeQuerier) GetUserByEmail(ctx context.Context, email string) (db.User, error) {
	return f.getUserByEmail(ctx, email)
}

var _ Querier = fakeQuerier{}

func newTestService(t *testing.T, queries Querier) *Service {
	t.Helper()

	return NewService(queries, newTestIssuer(t), false)
}

// hashOf is what the table would hold for a password.
func hashOf(t *testing.T, password string) string {
	t.Helper()

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.MinCost)
	if err != nil {
		t.Fatalf("hashing the test password: %v", err)
	}

	return string(hash)
}

// assertToken checks that the response carries a token this issuer accepts for
// the given account.
func assertToken(t *testing.T, issuer *Issuer, token *authv1.Token, wantUserID int64) {
	t.Helper()

	if token == nil {
		t.Fatal("response carries no token")
	}
	if !token.GetExpiresAt().IsValid() {
		t.Error("token carries no expiry")
	}

	userID, err := issuer.Verify(token.GetAccessToken())
	if err != nil {
		t.Fatalf("Verify() error = %v, want nil", err)
	}
	if userID != wantUserID {
		t.Errorf("token names user %d, want %d", userID, wantUserID)
	}
}

// A mixed-case address becomes the one form the table stores, so signing up
// twice with the same address in different case is the same account.
func TestServiceSignUpLowerCasesTheEmail(t *testing.T) {
	t.Parallel()

	var gotParams db.CreateUserParams
	issuer := newTestIssuer(t)
	svc := NewService(fakeQuerier{
		createUser: func(_ context.Context, arg db.CreateUserParams) (db.User, error) {
			gotParams = arg

			return db.User{ID: 3, Email: arg.Email}, nil
		},
	}, issuer, false)

	res, err := svc.SignUp(t.Context(), connect.NewRequest(&authv1.SignUpRequest{
		Email:    "User@Example.COM",
		Password: testPassword,
	}))
	if err != nil {
		t.Fatalf("SignUp() error = %v, want nil", err)
	}

	if diff := cmp.Diff(testEmail, gotParams.Email); diff != "" {
		t.Errorf("email passed to the query (-want +got):\n%s", diff)
	}
	// What is stored has to be a hash of the password, never the password.
	if gotParams.PasswordHash == testPassword {
		t.Error("the password was stored as given")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(gotParams.PasswordHash), []byte(testPassword)); err != nil {
		t.Errorf("stored hash does not match the password: %v", err)
	}

	assertToken(t, issuer, res.Msg.GetToken(), 3)
}

// The address is taken: the insert is what finds out, so that two requests
// racing cannot both get an account.
func TestServiceSignUpWithATakenEmail(t *testing.T) {
	t.Parallel()

	svc := newTestService(t, fakeQuerier{
		createUser: func(context.Context, db.CreateUserParams) (db.User, error) {
			return db.User{}, &pgconn.PgError{Code: uniqueViolation}
		},
	})

	_, err := svc.SignUp(t.Context(), connect.NewRequest(&authv1.SignUpRequest{
		Email:    testEmail,
		Password: testPassword,
	}))
	if got := connect.CodeOf(err); got != connect.CodeAlreadyExists {
		t.Errorf("SignUp() code = %v, want %v", got, connect.CodeAlreadyExists)
	}
}

func TestServiceSignUpInvalidCredentials(t *testing.T) {
	t.Parallel()

	tests := map[string]*authv1.SignUpRequest{
		"no email":           {Email: "", Password: testPassword},
		"not an address":     {Email: "nobody", Password: testPassword},
		"password too short": {Email: testEmail, Password: "1234567"},
		"password past bcrypt's limit": {
			Email:    testEmail,
			Password: string(make([]byte, maxPasswordLen+1)),
		},
	}

	for name, req := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			svc := newTestService(t, fakeQuerier{
				createUser: func(context.Context, db.CreateUserParams) (db.User, error) {
					t.Error("CreateUser called, want the request rejected first")

					return db.User{}, nil
				},
			})

			_, err := svc.SignUp(t.Context(), connect.NewRequest(req))
			if got := connect.CodeOf(err); got != connect.CodeInvalidArgument {
				t.Errorf("SignUp() code = %v, want %v", got, connect.CodeInvalidArgument)
			}
		})
	}
}

func TestServiceSignUpQueryError(t *testing.T) {
	t.Parallel()

	svc := newTestService(t, fakeQuerier{
		createUser: func(context.Context, db.CreateUserParams) (db.User, error) {
			return db.User{}, errQuery
		},
	})

	_, err := svc.SignUp(t.Context(), connect.NewRequest(&authv1.SignUpRequest{
		Email:    testEmail,
		Password: testPassword,
	}))
	if got := connect.CodeOf(err); got != connect.CodeInternal {
		t.Fatalf("SignUp() code = %v, want %v", got, connect.CodeInternal)
	}

	var connectErr *connect.Error
	if !errors.As(err, &connectErr) {
		t.Fatalf("SignUp() error = %v, want a *connect.Error", err)
	}
	if diff := cmp.Diff("internal error", connectErr.Message()); diff != "" {
		t.Errorf("client-facing message (-want +got):\n%s", diff)
	}
}

func TestServiceLogIn(t *testing.T) {
	t.Parallel()

	var gotEmail string
	issuer := newTestIssuer(t)
	svc := NewService(fakeQuerier{
		getUserByEmail: func(_ context.Context, email string) (db.User, error) {
			gotEmail = email

			return db.User{ID: 3, Email: email, PasswordHash: hashOf(t, testPassword)}, nil
		},
	}, issuer, false)

	res, err := svc.LogIn(t.Context(), connect.NewRequest(&authv1.LogInRequest{
		Email:    "USER@example.com",
		Password: testPassword,
	}))
	if err != nil {
		t.Fatalf("LogIn() error = %v, want nil", err)
	}

	if diff := cmp.Diff(testEmail, gotEmail); diff != "" {
		t.Errorf("email passed to the query (-want +got):\n%s", diff)
	}

	assertToken(t, issuer, res.Msg.GetToken(), 3)
}

// An unknown address and a wrong password are answered identically, so the API
// does not say which addresses have an account.
func TestServiceLogInRefusesBadCredentials(t *testing.T) {
	t.Parallel()

	tests := map[string]fakeQuerier{
		"unknown address": {
			getUserByEmail: func(context.Context, string) (db.User, error) {
				return db.User{}, pgx.ErrNoRows
			},
		},
		"wrong password": {
			getUserByEmail: func(_ context.Context, email string) (db.User, error) {
				return db.User{ID: 3, Email: email, PasswordHash: hashOf(t, "another password")}, nil
			},
		},
	}

	messages := make(map[string]string, len(tests))

	for name, queries := range tests {
		t.Run(name, func(t *testing.T) {
			svc := newTestService(t, queries)

			_, err := svc.LogIn(t.Context(), connect.NewRequest(&authv1.LogInRequest{
				Email:    testEmail,
				Password: testPassword,
			}))
			if got := connect.CodeOf(err); got != connect.CodeUnauthenticated {
				t.Fatalf("LogIn() code = %v, want %v", got, connect.CodeUnauthenticated)
			}

			var connectErr *connect.Error
			if !errors.As(err, &connectErr) {
				t.Fatalf("LogIn() error = %v, want a *connect.Error", err)
			}
			messages[name] = connectErr.Message()
		})
	}

	if diff := cmp.Diff(messages["unknown address"], messages["wrong password"]); diff != "" {
		t.Errorf("the two answers differ (-unknown address +wrong password):\n%s", diff)
	}
}

func TestServiceLogInQueryError(t *testing.T) {
	t.Parallel()

	svc := newTestService(t, fakeQuerier{
		getUserByEmail: func(context.Context, string) (db.User, error) {
			return db.User{}, errQuery
		},
	})

	_, err := svc.LogIn(t.Context(), connect.NewRequest(&authv1.LogInRequest{
		Email:    testEmail,
		Password: testPassword,
	}))
	if got := connect.CodeOf(err); got != connect.CodeInternal {
		t.Errorf("LogIn() code = %v, want %v", got, connect.CodeInternal)
	}
}

func TestServiceLogInInvalidCredentials(t *testing.T) {
	t.Parallel()

	tests := map[string]*authv1.LogInRequest{
		"not an address":     {Email: "nobody", Password: testPassword},
		"password too short": {Email: testEmail, Password: "1234567"},
	}

	for name, req := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			svc := newTestService(t, fakeQuerier{
				getUserByEmail: func(context.Context, string) (db.User, error) {
					t.Error("GetUserByEmail called, want the request rejected first")

					return db.User{}, nil
				},
			})

			_, err := svc.LogIn(t.Context(), connect.NewRequest(req))
			if got := connect.CodeOf(err); got != connect.CodeInvalidArgument {
				t.Errorf("LogIn() code = %v, want %v", got, connect.CodeInvalidArgument)
			}
		})
	}
}

func TestContextUserID(t *testing.T) {
	t.Parallel()

	if _, ok := UserIDFromContext(t.Context()); ok {
		t.Error("UserIDFromContext() ok = true on a bare context, want false")
	}

	userID, ok := UserIDFromContext(ContextWithUserID(t.Context(), 42))
	if !ok {
		t.Fatal("UserIDFromContext() ok = false, want true")
	}
	if userID != 42 {
		t.Errorf("UserIDFromContext() userID = %d, want 42", userID)
	}
}
