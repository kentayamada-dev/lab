package todo

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"connectrpc.com/connect"
	"github.com/google/go-cmp/cmp"
	"github.com/jackc/pgx/v5"
	"google.golang.org/protobuf/testing/protocmp"

	"example/app/gen/db"
	todov1 "example/app/gen/go/todo/v1"
)

type fakeQuerier struct {
	createTodo func(ctx context.Context, title string) (db.Todo, error)
	listTodos  func(ctx context.Context) ([]db.Todo, error)
	updateTodo func(ctx context.Context, arg db.UpdateTodoParams) (db.Todo, error)
}

func (f fakeQuerier) CreateTodo(ctx context.Context, title string) (db.Todo, error) {
	return f.createTodo(ctx, title)
}

func (f fakeQuerier) ListTodos(ctx context.Context) ([]db.Todo, error) {
	return f.listTodos(ctx)
}

func (f fakeQuerier) UpdateTodo(ctx context.Context, arg db.UpdateTodoParams) (db.Todo, error) {
	return f.updateTodo(ctx, arg)
}

var _ Querier = fakeQuerier{}

var errQuery = errors.New("query failed")

// assertNoLeak checks that the client-facing message hides the query error.
func assertNoLeak(t *testing.T, err error) {
	t.Helper()

	var connectErr *connect.Error
	if !errors.As(err, &connectErr) {
		t.Fatalf("error = %v, want a *connect.Error", err)
	}
	if diff := cmp.Diff("internal error", connectErr.Message()); diff != "" {
		t.Errorf("client-facing message (-want +got):\n%s", diff)
	}
}

func TestServiceCreateTodo(t *testing.T) {
	t.Parallel()

	var gotTitle string
	svc := NewService(fakeQuerier{
		createTodo: func(_ context.Context, title string) (db.Todo, error) {
			gotTitle = title

			return db.Todo{ID: 1, Title: title, Completed: false}, nil
		},
	})

	res, err := svc.CreateTodo(
		t.Context(),
		connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"}),
	)
	if err != nil {
		t.Fatalf("CreateTodo() error = %v, want nil", err)
	}

	if diff := cmp.Diff("buy milk", gotTitle); diff != "" {
		t.Errorf("title passed to the query (-want +got):\n%s", diff)
	}

	want := &todov1.Todo{Id: 1, Title: "buy milk", Done: false}
	if diff := cmp.Diff(want, res.Msg.GetTodo(), protocmp.Transform()); diff != "" {
		t.Errorf("CreateTodo() todo (-want +got):\n%s", diff)
	}
}

func TestServiceCreateTodoBlankTitle(t *testing.T) {
	t.Parallel()

	tests := map[string]string{
		"empty":            "",
		"whitespace only":  "   ",
		"tabs and newline": "\t\n",
	}

	for name, title := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			svc := NewService(fakeQuerier{
				createTodo: func(context.Context, string) (db.Todo, error) {
					t.Error("CreateTodo query called, want the request rejected first")

					return db.Todo{}, nil
				},
			})

			res, err := svc.CreateTodo(
				t.Context(),
				connect.NewRequest(&todov1.CreateTodoRequest{Title: title}),
			)
			if res != nil {
				t.Errorf("CreateTodo() response = %v, want nil", res)
			}
			if got := connect.CodeOf(err); got != connect.CodeInvalidArgument {
				t.Errorf("CreateTodo() code = %v, want %v", got, connect.CodeInvalidArgument)
			}
		})
	}
}

func TestServiceCreateTodoQueryError(t *testing.T) {
	t.Parallel()

	svc := NewService(fakeQuerier{
		createTodo: func(context.Context, string) (db.Todo, error) {
			return db.Todo{}, errQuery
		},
	})

	res, err := svc.CreateTodo(
		t.Context(),
		connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"}),
	)
	if res != nil {
		t.Errorf("CreateTodo() response = %v, want nil", res)
	}
	if got := connect.CodeOf(err); got != connect.CodeInternal {
		t.Errorf("CreateTodo() code = %v, want %v", got, connect.CodeInternal)
	}
	assertNoLeak(t, err)
}

func TestServiceListTodos(t *testing.T) {
	t.Parallel()

	tests := map[string]struct {
		rows []db.Todo
		want []*todov1.Todo
	}{
		"no todos": {
			rows: nil,
			want: []*todov1.Todo{},
		},
		"keeps the order returned by the query": {
			rows: []db.Todo{
				{ID: 2, Title: "buy milk", Completed: false},
				{ID: 5, Title: "walk the dog", Completed: true},
			},
			want: []*todov1.Todo{
				{Id: 2, Title: "buy milk", Done: false},
				{Id: 5, Title: "walk the dog", Done: true},
			},
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			svc := NewService(fakeQuerier{
				listTodos: func(context.Context) ([]db.Todo, error) {
					return tt.rows, nil
				},
			})

			res, err := svc.ListTodos(t.Context(), connect.NewRequest(&todov1.ListTodosRequest{}))
			if err != nil {
				t.Fatalf("ListTodos() error = %v, want nil", err)
			}

			if diff := cmp.Diff(tt.want, res.Msg.GetTodos(), protocmp.Transform()); diff != "" {
				t.Errorf("ListTodos() todos (-want +got):\n%s", diff)
			}
		})
	}
}

func TestServiceListTodosQueryError(t *testing.T) {
	t.Parallel()

	svc := NewService(fakeQuerier{
		listTodos: func(context.Context) ([]db.Todo, error) {
			return nil, errQuery
		},
	})

	res, err := svc.ListTodos(t.Context(), connect.NewRequest(&todov1.ListTodosRequest{}))
	if res != nil {
		t.Errorf("ListTodos() response = %v, want nil", res)
	}
	if got := connect.CodeOf(err); got != connect.CodeInternal {
		t.Errorf("ListTodos() code = %v, want %v", got, connect.CodeInternal)
	}
	assertNoLeak(t, err)
}

func TestServiceUpdateTodo(t *testing.T) {
	t.Parallel()

	var gotParams db.UpdateTodoParams
	svc := NewService(fakeQuerier{
		updateTodo: func(_ context.Context, arg db.UpdateTodoParams) (db.Todo, error) {
			gotParams = arg

			return db.Todo{ID: arg.ID, Title: "buy milk", Completed: arg.Completed}, nil
		},
	})

	res, err := svc.UpdateTodo(
		t.Context(),
		connect.NewRequest(&todov1.UpdateTodoRequest{Id: 7, Done: true}),
	)
	if err != nil {
		t.Fatalf("UpdateTodo() error = %v, want nil", err)
	}

	wantParams := db.UpdateTodoParams{ID: 7, Completed: true}
	if diff := cmp.Diff(wantParams, gotParams); diff != "" {
		t.Errorf("params passed to the query (-want +got):\n%s", diff)
	}

	want := &todov1.Todo{Id: 7, Title: "buy milk", Done: true}
	if diff := cmp.Diff(want, res.Msg.GetTodo(), protocmp.Transform()); diff != "" {
		t.Errorf("UpdateTodo() todo (-want +got):\n%s", diff)
	}
}

func TestServiceUpdateTodoErrors(t *testing.T) {
	t.Parallel()

	tests := map[string]struct {
		queryErr error
		wantCode connect.Code
	}{
		"unknown id": {
			queryErr: pgx.ErrNoRows,
			wantCode: connect.CodeNotFound,
		},
		"wrapped unknown id": {
			queryErr: fmt.Errorf("scanning row: %w", pgx.ErrNoRows),
			wantCode: connect.CodeNotFound,
		},
		"query failure": {
			queryErr: errQuery,
			wantCode: connect.CodeInternal,
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			svc := NewService(fakeQuerier{
				updateTodo: func(context.Context, db.UpdateTodoParams) (db.Todo, error) {
					return db.Todo{}, tt.queryErr
				},
			})

			res, err := svc.UpdateTodo(
				t.Context(),
				connect.NewRequest(&todov1.UpdateTodoRequest{Id: 42, Done: true}),
			)
			if res != nil {
				t.Errorf("UpdateTodo() response = %v, want nil", res)
			}
			if got := connect.CodeOf(err); got != tt.wantCode {
				t.Errorf("UpdateTodo() code = %v, want %v", got, tt.wantCode)
			}
			if tt.wantCode == connect.CodeInternal {
				assertNoLeak(t, err)
			}
		})
	}
}

func TestServiceUpdateTodoNotFoundMentionsID(t *testing.T) {
	t.Parallel()

	svc := NewService(fakeQuerier{
		updateTodo: func(context.Context, db.UpdateTodoParams) (db.Todo, error) {
			return db.Todo{}, pgx.ErrNoRows
		},
	})

	_, err := svc.UpdateTodo(t.Context(), connect.NewRequest(&todov1.UpdateTodoRequest{Id: 42}))

	var connectErr *connect.Error
	if !errors.As(err, &connectErr) {
		t.Fatalf("UpdateTodo() error = %v, want a *connect.Error", err)
	}
	if diff := cmp.Diff("todo 42 not found", connectErr.Message()); diff != "" {
		t.Errorf("UpdateTodo() message (-want +got):\n%s", diff)
	}
}
