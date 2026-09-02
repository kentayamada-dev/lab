package todo

import (
	"testing"
	"time"

	"github.com/google/go-cmp/cmp"
	"github.com/jackc/pgx/v5/pgtype"
	"google.golang.org/protobuf/testing/protocmp"
	"google.golang.org/protobuf/types/known/timestamppb"

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
				CreatedAt: pgtype.Timestamptz{Time: time.Unix(1_700_000_000, 5), Valid: true},
			},
			want: &todov1.Todo{
				Id:        1,
				Title:     "buy milk",
				Done:      false,
				CreatedAt: timestamppb.New(time.Unix(1_700_000_000, 5)),
			},
		},
		"completed todo": {
			row:  db.Todo{ID: 2, Title: "walk the dog", Completed: true},
			want: &todov1.Todo{Id: 2, Title: "walk the dog", Done: true},
		},
		// A NULL created_at cannot come from the schema, but the conversion
		// must not turn it into the Unix epoch.
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
