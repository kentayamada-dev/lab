package auth

import (
	"context"
	"errors"
	"testing"
	"time"

	"example/app/gen/db"
)

// stubSessions stands in for the sessions table, and records what it was asked
// about so a test can tell a lookup that never happened from one that did.
type stubSessions struct {
	open  bool
	err   error
	asked db.SessionExistsParams
}

func (s *stubSessions) SessionExists(_ context.Context, arg db.SessionExistsParams) (bool, error) {
	s.asked = arg

	return s.open, s.err
}

// newTestVerifier pairs a real issuer with the given sessions, so the tokens
// under test are ones the issuer actually signed.
func newTestVerifier(t *testing.T, sessions Sessions) (*Verifier, *Issuer) {
	t.Helper()

	issuer := newTestIssuer(t)

	return NewVerifier(issuer, sessions), issuer
}

func TestVerifierReturnsTheAccountTheTokenNames(t *testing.T) {
	t.Parallel()

	const (
		userID    int64 = 7
		sessionID int64 = 4
	)

	sessions := &stubSessions{open: true}
	verifier, issuer := newTestVerifier(t, sessions)

	got, err := verifier.Verify(t.Context(), issue(t, issuer, userID, sessionID, time.Now()))
	if err != nil {
		t.Fatalf("Verify() error = %v, want nil", err)
	}

	if got != userID {
		t.Errorf("Verify() = %d, want %d", got, userID)
	}
	// Both claims are looked up together, so a token pairing a session with an
	// account it was not opened for names nothing.
	want := db.SessionExistsParams{ID: sessionID, UserID: userID}
	if sessions.asked != want {
		t.Errorf("looked up %+v, want %+v", sessions.asked, want)
	}
}

// A signature cannot be withdrawn, so it is the row that says whether the
// session behind a token is still open: logging out deletes it, and deleting
// the account takes it along.
func TestVerifierRejectsATokenWhoseSessionIsClosed(t *testing.T) {
	t.Parallel()

	sessions := &stubSessions{open: false}
	verifier, issuer := newTestVerifier(t, sessions)

	_, err := verifier.Verify(t.Context(), issue(t, issuer, 7, 4, time.Now()))
	if !errors.Is(err, ErrRejected) {
		t.Errorf("Verify() error = %v, want one matching ErrRejected", err)
	}
}

// A token that does not verify is settled without the database, which is also
// what keeps an unauthenticated request from costing a query.
func TestVerifierRejectsATokenItCannotReadWithoutALookup(t *testing.T) {
	t.Parallel()

	sessions := &stubSessions{open: true}
	verifier, _ := newTestVerifier(t, sessions)

	_, err := verifier.Verify(t.Context(), "not-a-token")
	if !errors.Is(err, ErrRejected) {
		t.Errorf("Verify() error = %v, want one matching ErrRejected", err)
	}
	if (sessions.asked != db.SessionExistsParams{}) {
		t.Errorf("looked up %+v, want no lookup at all", sessions.asked)
	}
}

// Failing to find out is not a verdict on the token: reported as a rejection,
// it would tell a client to log in again over a database that is merely down.
func TestVerifierReportsALookupFailureAsItself(t *testing.T) {
	t.Parallel()

	wantErr := errors.New("the database is down")

	sessions := &stubSessions{err: wantErr}
	verifier, issuer := newTestVerifier(t, sessions)

	_, err := verifier.Verify(t.Context(), issue(t, issuer, 7, 4, time.Now()))
	if !errors.Is(err, wantErr) {
		t.Errorf("Verify() error = %v, want one matching %v", err, wantErr)
	}
	if errors.Is(err, ErrRejected) {
		t.Error("Verify() error matches ErrRejected, want the failure reported as itself")
	}
}
