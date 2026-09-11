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

// Issue returns a token naming userID, along with when it stops being
// accepted.
func (i *Issuer) Issue(userID int64, now time.Time) (string, time.Time, error) {
	expiresAt := now.Add(tokenTTL)

	signed, err := jwt.NewWithClaims(signingMethod, jwt.RegisteredClaims{
		Subject:   strconv.FormatInt(userID, 10),
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(expiresAt),
	}).SignedString(i.secret)
	if err != nil {
		return "", time.Time{}, err
	}

	return signed, expiresAt, nil
}

// Verify reads the user id out of a token, rejecting one that is not signed
// with the secret, has expired, or names no id an account could have.
func (i *Issuer) Verify(token string) (int64, error) {
	var claims jwt.RegisteredClaims

	_, err := jwt.ParseWithClaims(token, &claims,
		func(*jwt.Token) (any, error) { return i.secret, nil },
		jwt.WithValidMethods([]string{signingMethod.Alg()}),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return 0, err
	}

	// Ids are handed out by an identity column starting at 1, so anything
	// below that names no account however well the token is signed.
	userID, err := strconv.ParseInt(claims.Subject, 10, 64)
	if err != nil || userID < 1 {
		return 0, errors.New("token names no account")
	}

	return userID, nil
}
