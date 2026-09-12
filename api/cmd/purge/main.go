// Command purge erases the accounts whose grace period has run out.
//
// Closing an account only records that it was closed, so that one closed by
// mistake can still be restored (api/internal/account). Erasing it is this
// command's job, and nothing runs it on its own: it is meant for a scheduler
// outside the api, which is what keeps the promise the answer to DeleteAccount
// makes. Running it more often than the grace period costs nothing, since it
// erases only what is already past it, and running it twice at once is safe
// for the same reason.
package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"example/app/gen/db"
	"example/app/internal/account"
	"example/app/internal/config"
)

// timeout bounds the whole run. A purge that cannot finish in this is one a
// scheduler should be told about rather than one it should wait out.
const timeout = 5 * time.Minute

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stderr, nil)))

	if err := run(); err != nil {
		slog.Error("purge failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	dbURL, err := config.LoadDBURL()
	if err != nil {
		return err
	}

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	erased, err := account.Purge(ctx, db.New(pool), time.Now())
	if err != nil {
		return err
	}

	slog.InfoContext(ctx, "purged closed accounts",
		"erased", erased,
		"grace_period", account.GracePeriod.String(),
	)

	return nil
}
