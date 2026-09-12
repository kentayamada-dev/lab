package account

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

type fakePurger struct {
	purge func(ctx context.Context, closedBefore pgtype.Timestamptz) (int64, error)
}

func (f fakePurger) PurgeClosedAccounts(
	ctx context.Context,
	closedBefore pgtype.Timestamptz,
) (int64, error) {
	return f.purge(ctx, closedBefore)
}

// An account is erased once it has been closed for the whole grace period, so
// the cutoff the purge asks for is that far behind the moment it runs.
func TestPurgeAsksForTheAccountsPastTheGracePeriod(t *testing.T) {
	t.Parallel()

	now := time.Now()

	var got pgtype.Timestamptz

	erased, err := Purge(t.Context(), fakePurger{
		purge: func(_ context.Context, closedBefore pgtype.Timestamptz) (int64, error) {
			got = closedBefore

			return 2, nil
		},
	}, now)
	if err != nil {
		t.Fatalf("Purge() error = %v, want nil", err)
	}

	if !got.Valid {
		t.Fatal("the cutoff carries no instant")
	}
	if want := now.Add(-GracePeriod); !got.Time.Equal(want) {
		t.Errorf("cutoff = %v, want %v", got.Time, want)
	}
	if erased != 2 {
		t.Errorf("erased = %d, want 2", erased)
	}
}

// The purge instant an account is promised and the one the purge goes by are
// the same span apart, or an account would be erased early or kept late.
func TestPurgeAtAndClosedBeforeAgree(t *testing.T) {
	t.Parallel()

	closedAt := time.Now()

	// An account closed at closedAt is erased by a purge running exactly at the
	// instant it was promised, and not by one running a moment earlier.
	if ClosedBefore(PurgeAt(closedAt)).Before(closedAt) {
		t.Error("the account is still kept at the instant it was promised to be erased")
	}
	if !ClosedBefore(PurgeAt(closedAt).Add(-time.Second)).Before(closedAt) {
		t.Error("the account is erased before the instant it was promised")
	}
}
