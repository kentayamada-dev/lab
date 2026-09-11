package telemetry

import "testing"

// The generated queries are what the spans are mostly made of, so their names
// are what a trace has to show; anything else falls back to the operation, the
// way otelpgx names a statement it was given nothing better for.
func TestQueryName(t *testing.T) {
	tests := map[string]struct {
		sql  string
		want string
	}{
		"generated query": {
			sql:  "-- name: ListTodos :many\nSELECT * FROM todos\nWHERE user_id = $1",
			want: "ListTodos",
		},
		"generated query with leading blank lines": {
			sql:  "\n\n-- name: CreateUser :one\nINSERT INTO users (email) VALUES ($1)",
			want: "CreateUser",
		},
		"hand written statement": {
			sql:  "SELECT 1",
			want: "SELECT",
		},
		"comment that names nothing": {
			sql:  "-- a note\nSELECT 1",
			want: "--",
		},
		"empty statement": {
			sql:  "",
			want: "query",
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			if got := queryName(tt.sql); got != tt.want {
				t.Errorf("queryName() = %q, want %q", got, tt.want)
			}
		})
	}
}
