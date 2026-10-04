package main

import (
	"net/http"
)

func newMux() *http.ServeMux {
	mux := http.NewServeMux()
	// メソッドをパターンに含めると、GET 以外は ServeMux が 405 と Allow ヘッダーを返す（Go 1.22 以降）。
	// GET を登録すると HEAD も同じハンドラーに回る。
	// https://pkg.go.dev/net/http#hdr-Patterns-ServeMux
	mux.HandleFunc("GET /healthz", handleHealthz)
	return mux
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}
