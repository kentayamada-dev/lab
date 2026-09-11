package auth

import "context"

// userIDKey is unexported, so the value under it can only be put there by
// ContextWithUserID.
type userIDKey struct{}

// ContextWithUserID marks a request as belonging to an account.
func ContextWithUserID(ctx context.Context, userID int64) context.Context {
	return context.WithValue(ctx, userIDKey{}, userID)
}

// UserIDFromContext returns the account a request was authenticated as. The
// second result is false when the request never passed the authentication
// interceptor (api/internal/server/auth.go).
func UserIDFromContext(ctx context.Context) (int64, bool) {
	userID, ok := ctx.Value(userIDKey{}).(int64)

	return userID, ok
}
