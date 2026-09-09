package main

import "testing"

// The success path needs a live database, so what is pinned here is that every
// failure on the way to serving is reported instead of being swallowed.
func TestRunReportsSetupFailures(t *testing.T) {
	tests := map[string]struct {
		dbURL string
		port  string
	}{
		"missing database url": {
			dbURL: "",
			port:  "8080",
		},
		"invalid port": {
			dbURL: "postgres://user:pass@127.0.0.1:5432/app",
			port:  "not-a-port",
		},
		"unparsable database url": {
			dbURL: "postgres://user:pass@host:not-a-port/app",
			port:  "8080",
		},
		"unreachable database": {
			dbURL: "postgres://user:pass@127.0.0.1:1/app?connect_timeout=1",
			port:  "8080",
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Setenv("DB_URL", tt.dbURL)
			t.Setenv("PORT", tt.port)

			if err := run(); err == nil {
				t.Error("run() error = nil, want an error")
			}
		})
	}
}
