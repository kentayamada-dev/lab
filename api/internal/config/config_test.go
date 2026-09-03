package config

import (
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestLoad(t *testing.T) {
	t.Setenv("DB_URL", "postgres://user:pass@db:5432/app")
	t.Setenv("PORT", "8080")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v, want nil", err)
	}

	want := Config{
		DBURL: "postgres://user:pass@db:5432/app",
		Addr:  ":8080",
	}
	if diff := cmp.Diff(want, cfg); diff != "" {
		t.Errorf("Load() config (-want +got):\n%s", diff)
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
