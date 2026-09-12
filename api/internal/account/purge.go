package account

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

// Purger erases the accounts whose grace period is up. *db.Queries satisfies
// it.
type Purger interface {
	PurgeClosedAccounts(ctx context.Context, closedBefore pgtype.Timestamptz) (int64, error)
}

// Purge erases every account closed more than GracePeriod before now, and
// returns how many it erased. Their todos and any sessions that outlived the
// closing go with them, the foreign keys cascading (api/schema.sql).
//
// Nothing calls this while serving a request. Closing an account is what a
// client asks for, and erasing it is what the promise made in the answer costs
// (proto/account/v1/account.proto); an account whose owner never comes back is
// exactly the one no request would reach, so the work has to be started from
// outside (api/cmd/purge).
func Purge(ctx context.Context, purger Purger, now time.Time) (int64, error) {
	erased, err := purger.PurgeClosedAccounts(ctx, pgtype.Timestamptz{
		Time:  ClosedBefore(now),
		Valid: true,
	})
	if err != nil {
		return 0, fmt.Errorf("purging closed accounts: %w", err)
	}

	return erased, nil
}
