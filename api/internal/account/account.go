// Package account implements the AccountService Connect handlers, and the
// purge that finishes what closing an account starts (api/cmd/purge).
package account

import "time"

// GracePeriod is how long a closed account is kept before it is erased. It is
// the window an account closed by mistake can be restored in, which is an
// operator editing the row: the API offers no way back, a closed account being
// one that cannot log in (proto/account/v1/account.proto).
//
// Counted in days of 24 hours, which is what the purge compares against; no
// account is erased to the minute anyway, since the purge runs on a schedule
// of its own.
const GracePeriod = 30 * 24 * time.Hour

// PurgeAt returns when an account closed at closedAt stops existing.
func PurgeAt(closedAt time.Time) time.Time {
	return closedAt.Add(GracePeriod)
}

// ClosedBefore returns the instant an account has to have been closed before
// to be erased by a purge running at now.
func ClosedBefore(now time.Time) time.Time {
	return now.Add(-GracePeriod)
}
