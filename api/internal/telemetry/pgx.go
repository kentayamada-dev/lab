package telemetry

import (
	"strings"

	"github.com/exaring/otelpgx"
)

// sqlcNameFields are the two words sqlc writes before the name of every query
// it generates ("-- name: ListTodos :many").
var sqlcNameFields = [...]string{"--", "name:"}

// queryName names the span of one query. otelpgx takes the statement's first
// word, which for a generated query is the "--" of the comment sqlc puts above
// it, leaving every span and every db.operation.name reading "--". The name in
// that comment is what tells the queries apart, so it is used when it is there
// and the first word otherwise.
func queryName(sql string) string {
	line, _, _ := strings.Cut(strings.TrimSpace(sql), "\n")

	fields := strings.Fields(line)
	if len(fields) > len(sqlcNameFields) &&
		fields[0] == sqlcNameFields[0] && fields[1] == sqlcNameFields[1] {
		return fields[len(sqlcNameFields)]
	}

	if len(fields) == 0 {
		return "query"
	}

	return fields[0]
}

// NewPgxTracer records a span per query against the providers Setup installed.
// A pool is given it through its configuration (api/cmd/server/main.go).
func NewPgxTracer() *otelpgx.Tracer {
	return otelpgx.NewTracer(otelpgx.WithSpanNameFunc(queryName))
}
