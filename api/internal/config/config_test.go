package config

import (
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestLoad(t *testing.T) {
	t.Setenv("DB_URL", "postgres://user:pass@db:5432/app")
	t.Setenv("PORT", "8080")
	t.Setenv("CORS_ORIGINS", "http://localhost:8081, http://localhost:3000")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v, want nil", err)
	}

	want := Config{
		DBURL:       "postgres://user:pass@db:5432/app",
		Addr:        ":8080",
		CORSOrigins: []string{"http://localhost:8081", "http://localhost:3000"},
	}
	if diff := cmp.Diff(want, cfg); diff != "" {
		t.Errorf("Load() config (-want +got):\n%s", diff)
	}
}

// CORS_ORIGINS is the one optional setting: without it the API answers no
// cross-origin request (api/internal/server/cors.go).
func TestLoadWithoutCORSOrigins(t *testing.T) {
	t.Setenv("DB_URL", "postgres://user:pass@db:5432/app")
	t.Setenv("PORT", "8080")
	t.Setenv("CORS_ORIGINS", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v, want nil", err)
	}

	if cfg.CORSOrigins != nil {
		t.Errorf("Load() CORSOrigins = %v, want nil", cfg.CORSOrigins)
	}
}

// An origin the CORS handler could never match is caught here, where it names
// the value, rather than in the browser, where it would look like the API
// refusing a request it in fact answered.
func TestLoadInvalidCORSOrigins(t *testing.T) {
	values := []string{
		"localhost:8081",
		"http://localhost:8081/",
		"http://localhost:8081/docs",
		"*",
		"http://",
		"http://localhost:8081, nope",
	}

	for _, value := range values {
		t.Run(value, func(t *testing.T) {
			t.Setenv("DB_URL", "postgres://user:pass@db:5432/app")
			t.Setenv("PORT", "8080")
			t.Setenv("CORS_ORIGINS", value)

			cfg, err := Load()
			if err == nil {
				t.Fatal("Load() error = nil, want an error")
			}
			if diff := cmp.Diff(Config{}, cfg); diff != "" {
				t.Errorf("Load() config on error (-want +got):\n%s", diff)
			}
		})
	}
}

func TestLoadMissingEnv(t *testing.T) {
	tests := map[string]struct {
		dbURL   string
		apiPort string
	}{
		"DB_URL unset": {dbURL: "", apiPort: "8080"},
		"PORT unset":   {dbURL: "postgres://db", apiPort: ""},
		"both unset":   {dbURL: "", apiPort: ""},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Setenv("DB_URL", tt.dbURL)
			t.Setenv("PORT", tt.apiPort)

			cfg, err := Load()
			if err == nil {
				t.Fatal("Load() error = nil, want an error")
			}
			if diff := cmp.Diff(Config{}, cfg); diff != "" {
				t.Errorf("Load() config on error (-want +got):\n%s", diff)
			}
		})
	}
}

// A PORT that cannot be listened on is caught by Load rather than surfacing
// later, when the server tries to bind.
func TestLoadInvalidPort(t *testing.T) {
	ports := []string{"http", "8080a", "0", "-1", "65536", "0x1f90"}

	for _, port := range ports {
		t.Run(port, func(t *testing.T) {
			t.Setenv("DB_URL", "postgres://user:pass@db:5432/app")
			t.Setenv("PORT", port)

			cfg, err := Load()
			if err == nil {
				t.Fatal("Load() error = nil, want an error")
			}
			if diff := cmp.Diff(Config{}, cfg); diff != "" {
				t.Errorf("Load() config on error (-want +got):\n%s", diff)
			}
		})
	}
}
