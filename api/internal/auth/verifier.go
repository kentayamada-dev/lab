package auth

import (
	"context"
	"errors"
	"fmt"
)

// ErrRejected marks a token the API will not act on: one the issuer cannot
// read back, and one naming an account that is no longer there. Anything else
// Verify returns is a failure to find out rather than a verdict on the token,
// and the caller answers it as its own fault (api/internal/server/auth.go).
var ErrRejected = errors.New("token rejected")

// Accounts reports whether an account still exists. *db.Queries satisfies it.
type Accounts interface {
	UserExists(ctx context.Context, id int64) (bool, error)
}

// Verifier resolves the account a token names. A signature is not enough on
// its own: a token outlives the row it was issued for, so one naming a deleted
// account would otherwise authenticate a request no handler can serve. The
// lookup it costs is one query per request.
type Verifier struct {
	issuer   *Issuer
	accounts Accounts
}

func NewVerifier(issuer *Issuer, accounts Accounts) *Verifier {
	return &Verifier{issuer: issuer, accounts: accounts}
}

// Verify returns the account the token names, and ErrRejected when the token
// names none the API would act for.
func (v *Verifier) Verify(ctx context.Context, token string) (int64, error) {
	userID, err := v.issuer.Verify(token)
	if err != nil {
		return 0, fmt.Errorf("%w: %w", ErrRejected, err)
	}

	exists, err := v.accounts.UserExists(ctx, userID)
	if err != nil {
		return 0, fmt.Errorf("looking up account %d: %w", userID, err)
	}
	if !exists {
		return 0, fmt.Errorf("%w: account %d no longer exists", ErrRejected, userID)
	}

	return userID, nil
}
