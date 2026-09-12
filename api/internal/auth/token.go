// Package auth issues the bearer tokens the API is reached with and reads
// them back.
package auth

import (
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	// tokenTTL is how long an issued token stays valid. Nothing refreshes one,
	// so this is also how long a session lasts before the client has to log in
	// again.
	tokenTTL = 24 * time.Hour
	// minSecretLen is the shortest secret accepted, in bytes. HS256 keys any
	// length, so a short one fails nowhere until somebody guesses it; the
	// output of the hash is 32 bytes and there is no reason for the key to be
	// smaller.
	minSecretLen = 32
)

// signingMethod is fixed rather than read from the token, so a token that
// names another algorithm cannot talk the parser into accepting it.
var signingMethod = jwt.SigningMethodHS256

// Issuer signs and verifies tokens with one secret.
type Issuer struct {
	secret []byte
}

// NewIssuer rejects a secret too short to be worth signing with.
func NewIssuer(secret string) (*Issuer, error) {
	if len(secret) < minSecretLen {
		return nil, fmt.Errorf("the token secret must be at least %d bytes, got %d", minSecretLen, len(secret))
	}

	return &Issuer{secret: []byte(secret)}, nil
}

// Expiry returns when a token issued at now stops being accepted. The session
// row is written before the token that names it can be signed, and the row
// records the same instant, so the caller needs this before it has a token to
// read it off (service.go).
func (i *Issuer) Expiry(now time.Time) time.Time {
	return now.Add(tokenTTL)
}

// Issue returns a token naming the account and the session it was opened for.
// A signature cannot be withdrawn, so the session is what a token is good for
// only as long as its row is there (verifier.go).
func (i *Issuer) Issue(userID, sessionID int64, now, expiresAt time.Time) (string, error) {
	return jwt.NewWithClaims(signingMethod, jwt.RegisteredClaims{
		ID:        strconv.FormatInt(sessionID, 10),
		Subject:   strconv.FormatInt(userID, 10),
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(expiresAt),
	}).SignedString(i.secret)
}

// claimID reads one of the two ids a token names. Ids are handed out by an
// identity column starting at 1, so anything below that names no row however
// well the token is signed.
func claimID(claim string) (int64, error) {
	id, err := strconv.ParseInt(claim, 10, 64)
	if err != nil || id < 1 {
		return 0, errors.New("not an id any row could have")
	}

	return id, nil
}

// Verify reads the account and the session out of a token, rejecting one that
// is not signed with the secret, has expired, or names ids no row could have.
func (i *Issuer) Verify(token string) (userID, sessionID int64, err error) {
	var claims jwt.RegisteredClaims

	_, err = jwt.ParseWithClaims(token, &claims,
		func(*jwt.Token) (any, error) { return i.secret, nil },
		jwt.WithValidMethods([]string{signingMethod.Alg()}),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return 0, 0, err
	}

	userID, err = claimID(claims.Subject)
	if err != nil {
		return 0, 0, fmt.Errorf("token names no account: %w", err)
	}

	sessionID, err = claimID(claims.ID)
	if err != nil {
		return 0, 0, fmt.Errorf("token names no session: %w", err)
	}

	return userID, sessionID, nil
}
