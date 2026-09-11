package server

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"time"
)

// healthTimeout bounds the ping. A probe that hangs is read as a failure by
// whatever polls this endpoint, so answering late is no better than answering
// unhealthy, and holding the connection open is worse.
const healthTimeout = 2 * time.Second

// registerHealth serves the readiness probe. It pings the database rather than
// only answering from the process, because a server that cannot reach its
// database can serve no procedure and should be taken out of rotation.
func registerHealth(mux *http.ServeMux, health Pinger) {
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), healthTimeout)
		defer cancel()

		if err := health.Ping(ctx); err != nil {
			slog.ErrorContext(ctx, "health check failed", "error", err)
			http.Error(w, "unhealthy", http.StatusServiceUnavailable)

			return
		}

		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		if _, err := io.WriteString(w, "ok\n"); err != nil {
			slog.ErrorContext(ctx, "serving /healthz", "error", err)
		}
	})
}
