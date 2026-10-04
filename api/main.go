package main

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

func run() error {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	srv := &http.Server{
		Addr:    net.JoinHostPort("", port),
		Handler: newMux(),
		// http.Server の既定はどのタイムアウトも無制限で、ヘッダーを少しずつ送り続ける接続（Slowloris）に
		// 接続を握られ続ける。ヘッダーの読み込みだけは必ず打ち切る。
		ReadHeaderTimeout: 5 * time.Second,
	}

	// docker compose down などのコンテナ停止は SIGTERM を送るため、SIGINT（Ctrl+C）と合わせて受けて
	// 処理中のリクエストを捌き切ってから終了する
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	errCh := make(chan error, 1)
	go func() {
		slog.Info("listening", "addr", srv.Addr)
		errCh <- srv.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return err
	}
	// Shutdown が呼ばれると ListenAndServe は ErrServerClosed を返す。正常な停止なのでエラーにしない
	if err := <-errCh; !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}
