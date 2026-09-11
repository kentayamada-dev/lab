package main

import "testing"

// The success path needs a live database, so what is pinned here is that every
// failure on the way to serving is reported instead of being swallowed.
func TestRunReportsSetupFailures(t *testing.T) {
	tests := map[string]struct {
		dbURL       string
		port        string
		tokenSecret string
	}{
		"missing database url": {
			dbURL:       "",
			port:        "8080",
			tokenSecret: "token-secret-for-tests-only-0123",
		},
		"token secret too short to sign with": {
			dbURL:       "postgres://user:pass@127.0.0.1:5432/app",
			port:        "8080",
			tokenSecret: "short",
		},
		"invalid port": {
			dbURL:       "postgres://user:pass@127.0.0.1:5432/app",
			port:        "not-a-port",
			tokenSecret: "token-secret-for-tests-only-0123",
		},
		"unparsable database url": {
			dbURL:       "postgres://user:pass@host:not-a-port/app",
			port:        "8080",
			tokenSecret: "token-secret-for-tests-only-0123",
		},
		"unreachable database": {
			dbURL:       "postgres://user:pass@127.0.0.1:1/app?connect_timeout=1",
			port:        "8080",
			tokenSecret: "token-secret-for-tests-only-0123",
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Setenv("DB_URL", tt.dbURL)
			t.Setenv("PORT", tt.port)
			t.Setenv("TOKEN_SECRET", tt.tokenSecret)

			if err := run(); err == nil {
				t.Error("run() error = nil, want an error")
			}
		})
	}
}
