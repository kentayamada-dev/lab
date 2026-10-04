package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthz(t *testing.T) {
	tests := []struct {
		name       string
		method     string
		path       string
		wantStatus int
		wantBody   string
	}{
		{name: "GET は 200 と状態を返す", method: http.MethodGet, path: "/healthz",
			wantStatus: http.StatusOK, wantBody: `{"status":"ok"}`},
		{name: "HEAD も 200 を返す", method: http.MethodHead, path: "/healthz",
			wantStatus: http.StatusOK},
		{name: "POST は 405", method: http.MethodPost, path: "/healthz",
			wantStatus: http.StatusMethodNotAllowed},
		{name: "末尾スラッシュ付きは別パスとして 404", method: http.MethodGet, path: "/healthz/",
			wantStatus: http.StatusNotFound},
		{name: "未登録のパスは 404", method: http.MethodGet, path: "/",
			wantStatus: http.StatusNotFound},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			newMux().ServeHTTP(rec, httptest.NewRequestWithContext(t.Context(), tt.method, tt.path, nil))

			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d", rec.Code, tt.wantStatus)
			}
			if tt.wantBody == "" {
				return
			}
			if got := rec.Body.String(); got != tt.wantBody {
				t.Errorf("body = %q, want %q", got, tt.wantBody)
			}
			if got := rec.Header().Get("Content-Type"); got != "application/json" {
				t.Errorf("Content-Type = %q, want %q", got, "application/json")
			}
		})
	}
}

func TestHealthzAllowHeader(t *testing.T) {
	rec := httptest.NewRecorder()
	newMux().ServeHTTP(rec, httptest.NewRequestWithContext(t.Context(), http.MethodPost, "/healthz", nil))

	if got := rec.Header().Get("Allow"); got != "GET, HEAD" {
		t.Errorf("Allow = %q, want %q", got, "GET, HEAD")
	}
}
