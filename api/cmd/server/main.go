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
	"example/app/internal/auth"
	"example/app/internal/config"
	"example/app/internal/server"
	"example/app/internal/telemetry"
	"example/app/internal/todo"
)

// serviceName identifies this process in the telemetry it exports.
const serviceName = "api"

// telemetryFlushTimeout bounds the final export. It runs after the signal
// context is already cancelled, so it needs a deadline of its own.
const telemetryFlushTimeout = 5 * time.Second

func main() {
	// Wrapped so that every line logged while serving a request names the span
	// it belongs to (api/internal/telemetry/slog.go).
	slog.SetDefault(slog.New(telemetry.NewLogHandler(slog.NewJSONHandler(os.Stderr, nil))))

	if err := run(); err != nil {
		slog.Error("server stopped", "error", err)
		os.Exit(1)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	flushTelemetry, err := telemetry.Setup(ctx, serviceName)
	if err != nil {
		return err
	}
	defer func() {
		flushCtx, cancel := context.WithTimeout(context.Background(), telemetryFlushTimeout)
		defer cancel()

		if err := flushTelemetry(flushCtx); err != nil {
			slog.ErrorContext(flushCtx, "flushing telemetry", "error", err)
		}
	}()

	issuer, err := auth.NewIssuer(cfg.TokenSecret)
	if err != nil {
		return err
	}

	poolConfig, err := pgxpool.ParseConfig(cfg.DBURL)
	if err != nil {
		return err
	}
	// Records a span per query, so a slow call is read as the query it waited
	// on rather than as a handler that took a while for no stated reason.
	poolConfig.ConnConfig.Tracer = telemetry.NewPgxTracer()

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return err
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		return err
	}
	slog.InfoContext(ctx, "connected to database")

	queries := db.New(pool)

	srv, err := server.New(server.Deps{
		Addr:          cfg.Addr,
		CORSOrigins:   cfg.CORSOrigins,
		Health:        pool,
		Auth:          auth.NewService(queries, issuer, cfg.SecureCookies),
		Todo:          todo.NewService(queries),
		Authenticator: auth.NewVerifier(issuer, queries),
	})
	if err != nil {
		return err
	}

	return srv.Run(ctx)
}
