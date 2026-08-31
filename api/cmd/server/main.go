package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/jackc/pgx/v5/pgxpool"

	"example/app/gen/db"
	"example/app/internal/config"
	"example/app/internal/server"
	"example/app/internal/todo"
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	pool, err := pgxpool.New(ctx, cfg.DBURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		return err
	}
	log.Println("connected to database")

	return server.New(cfg.Addr, todo.NewService(db.New(pool))).Run(ctx)
}
