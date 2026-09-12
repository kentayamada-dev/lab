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

// issue signs a token the way the service does, for the tests that only need
// one back.
func issue(t *testing.T, issuer *Issuer, userID, sessionID int64, now time.Time) string {
	t.Helper()

	token, err := issuer.Issue(userID, sessionID, now, issuer.Expiry(now))
	if err != nil {
		t.Fatalf("Issue() error = %v, want nil", err)
	}

	return token
}

func TestIssuerRoundTrip(t *testing.T) {
	t.Parallel()

	issuer := newTestIssuer(t)
	now := time.Now()

	if want := now.Add(tokenTTL); !issuer.Expiry(now).Equal(want) {
		t.Errorf("Expiry() = %v, want %v", issuer.Expiry(now), want)
	}

	userID, sessionID, err := issuer.Verify(issue(t, issuer, 42, 9, now))
	if err != nil {
		t.Fatalf("Verify() error = %v, want nil", err)
	}
	if userID != 42 {
		t.Errorf("Verify() userID = %d, want 42", userID)
	}
	if sessionID != 9 {
		t.Errorf("Verify() sessionID = %d, want 9", sessionID)
	}
}

func TestIssuerVerifyRejects(t *testing.T) {
	t.Parallel()

	issuer := newTestIssuer(t)
	now := time.Now()

	expired := issue(t, issuer, 42, 9, now.Add(-2*tokenTTL))

	otherIssuer, err := NewIssuer(strings.Repeat("b", minSecretLen))
	if err != nil {
		t.Fatalf("NewIssuer() error = %v, want nil", err)
	}
	signedByAnother := issue(t, otherIssuer, 42, 9, now)

	valid := jwt.RegisteredClaims{
		ID:        "9",
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
			ID:       "9",
			Subject:  "42",
			IssuedAt: jwt.NewNumericDate(now),
		}),
		"subject is not a number": signWith(t, signingMethod, []byte(testSecret), jwt.RegisteredClaims{
			ID:        "9",
			Subject:   "nobody",
			ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL)),
		}),
		"subject is an id no account can have": signWith(t, signingMethod, []byte(testSecret), jwt.RegisteredClaims{
			ID:        "9",
			Subject:   "0",
			ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL)),
		}),
		// A token from before sessions existed would carry no jti, and naming
		// no session it names nothing that can be closed.
		"no session": signWith(t, signingMethod, []byte(testSecret), jwt.RegisteredClaims{
			Subject:   "42",
			ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL)),
		}),
		"session is an id no row can have": signWith(t, signingMethod, []byte(testSecret), jwt.RegisteredClaims{
			ID:        "0",
			Subject:   "42",
			ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL)),
		}),
	}

	for name, token := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			if _, _, err := issuer.Verify(token); err == nil {
				t.Error("Verify() error = nil, want an error")
			}
		})
	}
}
