package auth

import (
	"context"
	"errors"
	"fmt"

	"example/app/gen/db"
)

// ErrRejected marks a token the API will not act on: one the issuer cannot
// read back, and one whose session is no longer open. Anything else Verify
// returns is a failure to find out rather than a verdict on the token, and the
// caller answers it as its own fault (api/internal/server/auth.go).
var ErrRejected = errors.New("token rejected")

// Sessions reports whether a session is still open. *db.Queries satisfies it.
type Sessions interface {
	SessionExists(ctx context.Context, arg db.SessionExistsParams) (bool, error)
}

// Verifier resolves the account a token names. A signature is not enough on
// its own, because it cannot be taken back: the session row is what logging
// out deletes (service.go), and the row's reference to the account is what
// takes the sessions of a deleted one with it (api/schema.sql). The lookup it
// costs is one query per request.
type Verifier struct {
	issuer   *Issuer
	sessions Sessions
}

func NewVerifier(issuer *Issuer, sessions Sessions) *Verifier {
	return &Verifier{issuer: issuer, sessions: sessions}
}

// Verify returns the account the token names, and ErrRejected when the token
// names none the API would act for.
func (v *Verifier) Verify(ctx context.Context, token string) (int64, error) {
	userID, sessionID, err := v.issuer.Verify(token)
	if err != nil {
		return 0, fmt.Errorf("%w: %w", ErrRejected, err)
	}

	open, err := v.sessions.SessionExists(ctx, db.SessionExistsParams{
		ID:     sessionID,
		UserID: userID,
	})
	if err != nil {
		return 0, fmt.Errorf("looking up session %d: %w", sessionID, err)
	}
	if !open {
		return 0, fmt.Errorf("%w: session %d is no longer open", ErrRejected, sessionID)
	}

	return userID, nil
}
