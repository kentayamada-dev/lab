package config

import (
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestLoad(t *testing.T) {
	t.Setenv("DB_URL", "postgres://user:pass@db:5432/app")
	t.Setenv("PORT", "8080")
	t.Setenv("TOKEN_SECRET", "token-secret-for-tests-only-0123")
	t.Setenv("COOKIE_SECURE", "true")
	t.Setenv("CORS_ORIGINS", "http://localhost:8081, http://localhost:3000")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v, want nil", err)
	}

	want := Config{
		DBURL:         "postgres://user:pass@db:5432/app",
		Addr:          ":8080",
		TokenSecret:   "token-secret-for-tests-only-0123",
		SecureCookies: true,
		CORSOrigins:   []string{"http://localhost:8081", "http://localhost:3000"},
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
	t.Setenv("TOKEN_SECRET", "token-secret-for-tests-only-0123")
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
			t.Setenv("TOKEN_SECRET", "token-secret-for-tests-only-0123")
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
		dbURL       string
		apiPort     string
		tokenSecret string
	}{
		"DB_URL unset":       {dbURL: "", apiPort: "8080", tokenSecret: "token-secret-for-tests-only-0123"},
		"PORT unset":         {dbURL: "postgres://db", apiPort: "", tokenSecret: "token-secret-for-tests-only-0123"},
		"TOKEN_SECRET unset": {dbURL: "postgres://db", apiPort: "8080", tokenSecret: ""},
		"all unset":          {dbURL: "", apiPort: "", tokenSecret: ""},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Setenv("DB_URL", tt.dbURL)
			t.Setenv("PORT", tt.apiPort)
			t.Setenv("TOKEN_SECRET", tt.tokenSecret)

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
			t.Setenv("TOKEN_SECRET", "token-secret-for-tests-only-0123")

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

// Forgetting the setting must not be what offers the session cookie over plain
// http, so an unset COOKIE_SECURE is the safe answer rather than the lax one.
func TestLoadWithoutCookieSecure(t *testing.T) {
	t.Setenv("DB_URL", "postgres://user:pass@db:5432/app")
	t.Setenv("PORT", "8080")
	t.Setenv("TOKEN_SECRET", "token-secret-for-tests-only-0123")
	t.Setenv("COOKIE_SECURE", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v, want nil", err)
	}

	if !cfg.SecureCookies {
		t.Error("Load() SecureCookies = false, want true when unset")
	}
}

func TestLoadCookieSecureOff(t *testing.T) {
	t.Setenv("DB_URL", "postgres://user:pass@db:5432/app")
	t.Setenv("PORT", "8080")
	t.Setenv("TOKEN_SECRET", "token-secret-for-tests-only-0123")
	t.Setenv("COOKIE_SECURE", "false")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v, want nil", err)
	}

	if cfg.SecureCookies {
		t.Error("Load() SecureCookies = true, want the setting to be able to turn it off")
	}
}

// A value that cannot be read as a boolean is an error rather than a quiet
// false, which would leave a misspelling looking like a deliberate off.
func TestLoadInvalidCookieSecure(t *testing.T) {
	for _, value := range []string{"maybe", "yes please", "2"} {
		t.Run(value, func(t *testing.T) {
			t.Setenv("DB_URL", "postgres://user:pass@db:5432/app")
			t.Setenv("PORT", "8080")
			t.Setenv("TOKEN_SECRET", "token-secret-for-tests-only-0123")
			t.Setenv("COOKIE_SECURE", value)

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
