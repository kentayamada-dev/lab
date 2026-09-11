package auth

import (
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// testSecret is exactly the shortest secret NewIssuer accepts.
const testSecret = "token-secret-for-tests-only-0123"

func newTestIssuer(t *testing.T) *Issuer {
	t.Helper()

	issuer, err := NewIssuer(testSecret)
	if err != nil {
		t.Fatalf("NewIssuer() error = %v, want nil", err)
	}

	return issuer
}

// signWith builds a token the way an attacker with a given secret and method
// would, bypassing Issue so the parser's own guards are what is tested.
func signWith(t *testing.T, method jwt.SigningMethod, key any, claims jwt.Claims) string {
	t.Helper()

	signed, err := jwt.NewWithClaims(method, claims).SignedString(key)
	if err != nil {
		t.Fatalf("signing the test token: %v", err)
	}

	return signed
}

func TestNewIssuerRejectsAShortSecret(t *testing.T) {
	t.Parallel()

	if _, err := NewIssuer(strings.Repeat("a", minSecretLen-1)); err == nil {
		t.Error("NewIssuer() error = nil, want an error")
	}
}

func TestIssuerRoundTrip(t *testing.T) {
	t.Parallel()

	issuer := newTestIssuer(t)
	now := time.Now()

	token, expiresAt, err := issuer.Issue(42, now)
	if err != nil {
		t.Fatalf("Issue() error = %v, want nil", err)
	}

	if want := now.Add(tokenTTL); !expiresAt.Equal(want) {
		t.Errorf("Issue() expiresAt = %v, want %v", expiresAt, want)
	}

	userID, err := issuer.Verify(token)
	if err != nil {
		t.Fatalf("Verify() error = %v, want nil", err)
	}
	if userID != 42 {
		t.Errorf("Verify() userID = %d, want 42", userID)
	}
}

func TestIssuerVerifyRejects(t *testing.T) {
	t.Parallel()

	issuer := newTestIssuer(t)
	now := time.Now()

	expired, _, err := issuer.Issue(42, now.Add(-2*tokenTTL))
	if err != nil {
		t.Fatalf("Issue() error = %v, want nil", err)
	}

	otherIssuer, err := NewIssuer(strings.Repeat("b", minSecretLen))
	if err != nil {
		t.Fatalf("NewIssuer() error = %v, want nil", err)
	}
	signedByAnother, _, err := otherIssuer.Issue(42, now)
	if err != nil {
		t.Fatalf("Issue() error = %v, want nil", err)
	}

	valid := jwt.RegisteredClaims{
		Subject:   "42",
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL)),
	}

	tests := map[string]string{
		"empty":             "",
		"not a token":       "not-a-token",
		"expired":           expired,
		"signed by another": signedByAnother,
		"unsigned":          signWith(t, jwt.SigningMethodNone, jwt.UnsafeAllowNoneSignatureType, valid),
		"another algorithm": signWith(t, jwt.SigningMethodHS512, []byte(testSecret), valid),
		"no expiry": signWith(t, signingMethod, []byte(testSecret), jwt.RegisteredClaims{
			Subject:  "42",
			IssuedAt: jwt.NewNumericDate(now),
		}),
		"subject is not a number": signWith(t, signingMethod, []byte(testSecret), jwt.RegisteredClaims{
			Subject:   "nobody",
			ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL)),
		}),
		"subject is an id no account can have": signWith(t, signingMethod, []byte(testSecret), jwt.RegisteredClaims{
			Subject:   "0",
			ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL)),
		}),
	}

	for name, token := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			if _, err := issuer.Verify(token); err == nil {
				t.Error("Verify() error = nil, want an error")
			}
		})
	}
}
