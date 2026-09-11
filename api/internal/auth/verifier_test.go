package auth

import (
	"context"
	"errors"
	"testing"
	"time"
)

// stubAccounts stands in for the users table, and records what it was asked
// about so a test can tell a lookup that never happened from one that did.
type stubAccounts struct {
	exists bool
	err    error
	asked  int64
}

func (a *stubAccounts) UserExists(_ context.Context, id int64) (bool, error) {
	a.asked = id

	return a.exists, a.err
}

// newTestVerifier pairs a real issuer with the given accounts, so the tokens
// under test are ones the issuer actually signed.
func newTestVerifier(t *testing.T, accounts Accounts) (*Verifier, *Issuer) {
	t.Helper()

	issuer := newTestIssuer(t)

	return NewVerifier(issuer, accounts), issuer
}

func issueFor(t *testing.T, issuer *Issuer, userID int64) string {
	t.Helper()

	token, _, err := issuer.Issue(userID, time.Now())
	if err != nil {
		t.Fatalf("Issue() error = %v, want nil", err)
	}

	return token
}

func TestVerifierReturnsTheAccountTheTokenNames(t *testing.T) {
	t.Parallel()

	const userID int64 = 7

	accounts := &stubAccounts{exists: true}
	verifier, issuer := newTestVerifier(t, accounts)

	got, err := verifier.Verify(t.Context(), issueFor(t, issuer, userID))
	if err != nil {
		t.Fatalf("Verify() error = %v, want nil", err)
	}

	if got != userID {
		t.Errorf("Verify() = %d, want %d", got, userID)
	}
	if accounts.asked != userID {
		t.Errorf("looked up account %d, want %d", accounts.asked, userID)
	}
}

// A token outlives the row it was issued for, so the signature alone cannot
// settle whether there is still an account to act for.
func TestVerifierRejectsATokenWhoseAccountIsGone(t *testing.T) {
	t.Parallel()

	accounts := &stubAccounts{exists: false}
	verifier, issuer := newTestVerifier(t, accounts)

	_, err := verifier.Verify(t.Context(), issueFor(t, issuer, 7))
	if !errors.Is(err, ErrRejected) {
		t.Errorf("Verify() error = %v, want one matching ErrRejected", err)
	}
}

// A token that does not verify is settled without the database, which is also
// what keeps an unauthenticated request from costing a query.
func TestVerifierRejectsATokenItCannotReadWithoutALookup(t *testing.T) {
	t.Parallel()

	accounts := &stubAccounts{exists: true}
	verifier, _ := newTestVerifier(t, accounts)

	_, err := verifier.Verify(t.Context(), "not-a-token")
	if !errors.Is(err, ErrRejected) {
		t.Errorf("Verify() error = %v, want one matching ErrRejected", err)
	}
	if accounts.asked != 0 {
		t.Errorf("looked up account %d, want no lookup at all", accounts.asked)
	}
}

// Failing to find out is not a verdict on the token: reported as a rejection,
// it would tell a client to log in again over a database that is merely down.
func TestVerifierReportsALookupFailureAsItself(t *testing.T) {
	t.Parallel()

	wantErr := errors.New("the database is down")

	accounts := &stubAccounts{err: wantErr}
	verifier, issuer := newTestVerifier(t, accounts)

	_, err := verifier.Verify(t.Context(), issueFor(t, issuer, 7))
	if !errors.Is(err, wantErr) {
		t.Errorf("Verify() error = %v, want one matching %v", err, wantErr)
	}
	if errors.Is(err, ErrRejected) {
		t.Error("Verify() error matches ErrRejected, want the failure reported as itself")
	}
}
