package todo

import (
	"testing"
	"time"

	"github.com/google/go-cmp/cmp"
	"github.com/jackc/pgx/v5/pgtype"
	"google.golang.org/protobuf/testing/protocmp"

	"example/app/gen/db"
	todov1 "example/app/gen/go/todo/v1"
)

func TestToProtoTodo(t *testing.T) {
	t.Parallel()

	tests := map[string]struct {
		row  db.Todo
		want *todov1.Todo
	}{
		"pending todo": {
			row: db.Todo{
				ID:        1,
				Title:     "buy milk",
				Completed: false,
				CreatedAt: pgtype.Timestamptz{Time: time.Unix(0, 0), Valid: true},
			},
			want: &todov1.Todo{Id: 1, Title: "buy milk", Done: false},
		},
		"completed todo": {
			row:  db.Todo{ID: 2, Title: "walk the dog", Completed: true},
			want: &todov1.Todo{Id: 2, Title: "walk the dog", Done: true},
		},
		"zero value": {
			row:  db.Todo{},
			want: &todov1.Todo{},
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			if diff := cmp.Diff(tt.want, toProtoTodo(tt.row), protocmp.Transform()); diff != "" {
				t.Errorf("toProtoTodo() (-want +got):\n%s", diff)
			}
		})
	}
}
