package todo

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	"connectrpc.com/connect"
	"github.com/google/go-cmp/cmp"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/testing/protocmp"

	"example/app/gen/db"
	todov1 "example/app/gen/go/todo/v1"
	"example/app/internal/auth"
)

type fakeQuerier struct {
	createTodo func(ctx context.Context, arg db.CreateTodoParams) (db.Todo, error)
	listTodos  func(ctx context.Context, arg db.ListTodosParams) ([]db.Todo, error)
	updateTodo func(ctx context.Context, arg db.UpdateTodoParams) (db.Todo, error)
	deleteTodo func(ctx context.Context, arg db.DeleteTodoParams) (int64, error)
}

func (f fakeQuerier) CreateTodo(ctx context.Context, arg db.CreateTodoParams) (db.Todo, error) {
	return f.createTodo(ctx, arg)
}

func (f fakeQuerier) ListTodos(ctx context.Context, arg db.ListTodosParams) ([]db.Todo, error) {
	return f.listTodos(ctx, arg)
}

func (f fakeQuerier) UpdateTodo(ctx context.Context, arg db.UpdateTodoParams) (db.Todo, error) {
	return f.updateTodo(ctx, arg)
}

func (f fakeQuerier) DeleteTodo(ctx context.Context, arg db.DeleteTodoParams) (int64, error) {
	return f.deleteTodo(ctx, arg)
}

var _ Querier = fakeQuerier{}

var errQuery = errors.New("query failed")

// testUserID stands for the account the authentication interceptor resolved
// (api/internal/server/auth.go); every call below is made as that account.
const testUserID int64 = 7

func authed(t *testing.T) context.Context {
	t.Helper()

	return auth.ContextWithUserID(t.Context(), testUserID)
}

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

	var gotParams db.CreateTodoParams
	svc := NewService(fakeQuerier{
		createTodo: func(_ context.Context, arg db.CreateTodoParams) (db.Todo, error) {
			gotParams = arg

			return db.Todo{ID: 1, Title: arg.Title, Completed: false}, nil
		},
	})

	res, err := svc.CreateTodo(
		authed(t),
		connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"}),
	)
	if err != nil {
		t.Fatalf("CreateTodo() error = %v, want nil", err)
	}

	wantParams := db.CreateTodoParams{UserID: testUserID, Title: "buy milk"}
	if diff := cmp.Diff(wantParams, gotParams); diff != "" {
		t.Errorf("params passed to the query (-want +got):\n%s", diff)
	}

	want := &todov1.Todo{Id: 1, Title: "buy milk", Done: false}
	if diff := cmp.Diff(want, res.Msg.GetTodo(), protocmp.Transform()); diff != "" {
		t.Errorf("CreateTodo() todo (-want +got):\n%s", diff)
	}
}

func TestServiceCreateTodoTrimsTitle(t *testing.T) {
	t.Parallel()

	var gotParams db.CreateTodoParams
	svc := NewService(fakeQuerier{
		createTodo: func(_ context.Context, arg db.CreateTodoParams) (db.Todo, error) {
			gotParams = arg

			return db.Todo{ID: 1, Title: arg.Title, Completed: false}, nil
		},
	})

	_, err := svc.CreateTodo(
		authed(t),
		connect.NewRequest(&todov1.CreateTodoRequest{Title: "  buy milk\t\n"}),
	)
	if err != nil {
		t.Fatalf("CreateTodo() error = %v, want nil", err)
	}

	wantParams := db.CreateTodoParams{UserID: testUserID, Title: "buy milk"}
	if diff := cmp.Diff(wantParams, gotParams); diff != "" {
		t.Errorf("params passed to the query (-want +got):\n%s", diff)
	}
}

func TestServiceCreateTodoTitleLength(t *testing.T) {
	t.Parallel()

	// Multibyte runes pin the limit to runes rather than bytes.
	tests := map[string]struct {
		title    string
		wantCode connect.Code
	}{
		"at the limit": {
			title:    strings.Repeat("あ", 1000),
			wantCode: 0,
		},
		"one over the limit": {
			title:    strings.Repeat("あ", 1001),
			wantCode: connect.CodeInvalidArgument,
		},
		"over the limit after trimming does not count the whitespace": {
			title:    " " + strings.Repeat("あ", 1000) + " ",
			wantCode: 0,
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			svc := NewService(fakeQuerier{
				createTodo: func(_ context.Context, arg db.CreateTodoParams) (db.Todo, error) {
					if tt.wantCode != 0 {
						t.Error("CreateTodo query called, want the request rejected first")
					}

					return db.Todo{ID: 1, Title: arg.Title, Completed: false}, nil
				},
			})

			_, err := svc.CreateTodo(
				authed(t),
				connect.NewRequest(&todov1.CreateTodoRequest{Title: tt.title}),
			)
			if tt.wantCode == 0 {
				if err != nil {
					t.Errorf("CreateTodo() error = %v, want nil", err)
				}
			} else if got := connect.CodeOf(err); got != tt.wantCode {
				t.Errorf("CreateTodo() code = %v, want %v", got, tt.wantCode)
			}
		})
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
				createTodo: func(context.Context, db.CreateTodoParams) (db.Todo, error) {
					t.Error("CreateTodo query called, want the request rejected first")

					return db.Todo{}, nil
				},
			})

			res, err := svc.CreateTodo(
				authed(t),
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
		createTodo: func(context.Context, db.CreateTodoParams) (db.Todo, error) {
			return db.Todo{}, errQuery
		},
	})

	res, err := svc.CreateTodo(
		authed(t),
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
				listTodos: func(context.Context, db.ListTodosParams) ([]db.Todo, error) {
					return tt.rows, nil
				},
			})

			res, err := svc.ListTodos(authed(t), connect.NewRequest(&todov1.ListTodosRequest{}))
			if err != nil {
				t.Fatalf("ListTodos() error = %v, want nil", err)
			}

			if diff := cmp.Diff(tt.want, res.Msg.GetTodos(), protocmp.Transform()); diff != "" {
				t.Errorf("ListTodos() todos (-want +got):\n%s", diff)
			}
			if got := res.Msg.GetNextPageToken(); got != "" {
				t.Errorf("ListTodos() next page token = %q, want empty on the last page", got)
			}
		})
	}
}

// The query is asked for one row beyond the page so the service can tell
// whether a further page exists.
func TestServiceListTodosPageParams(t *testing.T) {
	t.Parallel()

	tests := map[string]struct {
		req        *todov1.ListTodosRequest
		wantParams db.ListTodosParams
	}{
		"defaults": {
			req:        &todov1.ListTodosRequest{},
			wantParams: db.ListTodosParams{UserID: testUserID, AfterID: 0, PageSize: defaultPageSize + 1},
		},
		"explicit page size": {
			req:        &todov1.ListTodosRequest{PageSize: 10},
			wantParams: db.ListTodosParams{UserID: testUserID, AfterID: 0, PageSize: 11},
		},
		"page size at the maximum": {
			req:        &todov1.ListTodosRequest{PageSize: maxPageSize},
			wantParams: db.ListTodosParams{UserID: testUserID, AfterID: 0, PageSize: maxPageSize + 1},
		},
		"page token becomes the cursor": {
			req:        &todov1.ListTodosRequest{PageSize: 2, PageToken: "42"},
			wantParams: db.ListTodosParams{UserID: testUserID, AfterID: 42, PageSize: 3},
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			var gotParams db.ListTodosParams
			svc := NewService(fakeQuerier{
				listTodos: func(_ context.Context, arg db.ListTodosParams) ([]db.Todo, error) {
					gotParams = arg

					return nil, nil
				},
			})

			if _, err := svc.ListTodos(authed(t), connect.NewRequest(tt.req)); err != nil {
				t.Fatalf("ListTodos() error = %v, want nil", err)
			}

			if diff := cmp.Diff(tt.wantParams, gotParams); diff != "" {
				t.Errorf("params passed to the query (-want +got):\n%s", diff)
			}
		})
	}
}

func TestServiceListTodosNextPageToken(t *testing.T) {
	t.Parallel()

	// Four rows come back for a page of three, so the fourth is the probe row.
	rows := []db.Todo{
		{ID: 2, Title: "one"},
		{ID: 4, Title: "two"},
		{ID: 6, Title: "three"},
		{ID: 8, Title: "four"},
	}

	tests := map[string]struct {
		rows      []db.Todo
		wantIDs   []int64
		wantToken string
	}{
		"a further page exists": {
			rows:      rows,
			wantIDs:   []int64{2, 4, 6},
			wantToken: "6",
		},
		"the page is exactly full": {
			rows:      rows[:3],
			wantIDs:   []int64{2, 4, 6},
			wantToken: "",
		},
		"the page is short": {
			rows:      rows[:1],
			wantIDs:   []int64{2},
			wantToken: "",
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			svc := NewService(fakeQuerier{
				listTodos: func(context.Context, db.ListTodosParams) ([]db.Todo, error) {
					return tt.rows, nil
				},
			})

			res, err := svc.ListTodos(
				authed(t),
				connect.NewRequest(&todov1.ListTodosRequest{PageSize: 3}),
			)
			if err != nil {
				t.Fatalf("ListTodos() error = %v, want nil", err)
			}

			gotIDs := make([]int64, 0, len(res.Msg.GetTodos()))
			for _, todo := range res.Msg.GetTodos() {
				gotIDs = append(gotIDs, todo.GetId())
			}
			if diff := cmp.Diff(tt.wantIDs, gotIDs); diff != "" {
				t.Errorf("ListTodos() ids (-want +got):\n%s", diff)
			}
			if diff := cmp.Diff(tt.wantToken, res.Msg.GetNextPageToken()); diff != "" {
				t.Errorf("ListTodos() next page token (-want +got):\n%s", diff)
			}
		})
	}
}

func TestServiceListTodosInvalidPageRequest(t *testing.T) {
	t.Parallel()

	tests := map[string]*todov1.ListTodosRequest{
		"negative page size": {
			PageSize: -1,
		},
		"page size over the max": {
			PageSize: maxPageSize + 1,
		},
		"token that is not a number": {
			PageToken: "abc",
		},
		"token that is zero": {
			PageToken: "0",
		},
		"negative token": {
			PageToken: "-1",
		},
	}

	for name, req := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			svc := NewService(fakeQuerier{
				listTodos: func(context.Context, db.ListTodosParams) ([]db.Todo, error) {
					t.Error("ListTodos query called, want the request rejected first")

					return nil, nil
				},
			})

			res, err := svc.ListTodos(authed(t), connect.NewRequest(req))
			if res != nil {
				t.Errorf("ListTodos() response = %v, want nil", res)
			}
			if got := connect.CodeOf(err); got != connect.CodeInvalidArgument {
				t.Errorf("ListTodos() code = %v, want %v", got, connect.CodeInvalidArgument)
			}
		})
	}
}

func TestServiceListTodosQueryError(t *testing.T) {
	t.Parallel()

	svc := NewService(fakeQuerier{
		listTodos: func(context.Context, db.ListTodosParams) ([]db.Todo, error) {
			return nil, errQuery
		},
	})

	res, err := svc.ListTodos(authed(t), connect.NewRequest(&todov1.ListTodosRequest{}))
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

			return db.Todo{ID: arg.ID, Title: "buy milk", Completed: arg.Completed.Bool}, nil
		},
	})

	res, err := svc.UpdateTodo(
		authed(t),
		connect.NewRequest(&todov1.UpdateTodoRequest{Id: 7, Done: proto.Bool(true)}),
	)
	if err != nil {
		t.Fatalf("UpdateTodo() error = %v, want nil", err)
	}

	wantParams := db.UpdateTodoParams{ID: 7, UserID: testUserID, Completed: pgtype.Bool{Bool: true, Valid: true}}
	if diff := cmp.Diff(wantParams, gotParams); diff != "" {
		t.Errorf("params passed to the query (-want +got):\n%s", diff)
	}

	want := &todov1.Todo{Id: 7, Title: "buy milk", Done: true}
	if diff := cmp.Diff(want, res.Msg.GetTodo(), protocmp.Transform()); diff != "" {
		t.Errorf("UpdateTodo() todo (-want +got):\n%s", diff)
	}
}

func TestServiceUpdateTodoWithTitle(t *testing.T) {
	t.Parallel()

	var gotParams db.UpdateTodoParams
	svc := NewService(fakeQuerier{
		updateTodo: func(_ context.Context, arg db.UpdateTodoParams) (db.Todo, error) {
			gotParams = arg

			return db.Todo{ID: arg.ID, Title: arg.Title.String, Completed: arg.Completed.Bool}, nil
		},
	})

	_, err := svc.UpdateTodo(
		authed(t),
		connect.NewRequest(&todov1.UpdateTodoRequest{Id: 7, Done: proto.Bool(true), Title: proto.String("  walk the dog  ")}),
	)
	if err != nil {
		t.Fatalf("UpdateTodo() error = %v, want nil", err)
	}

	wantParams := db.UpdateTodoParams{
		ID:        7,
		UserID:    testUserID,
		Completed: pgtype.Bool{Bool: true, Valid: true},
		Title:     pgtype.Text{String: "walk the dog", Valid: true},
	}
	if diff := cmp.Diff(wantParams, gotParams); diff != "" {
		t.Errorf("params passed to the query (-want +got):\n%s", diff)
	}
}

// An absent field reaches the query as a NULL parameter, which the query's
// coalesce turns into "keep the current value". A request with no field at all
// is rejected instead, see TestServiceUpdateTodoNoFields.
func TestServiceUpdateTodoLeavesAbsentFieldsUntouched(t *testing.T) {
	t.Parallel()

	tests := map[string]struct {
		req        *todov1.UpdateTodoRequest
		wantParams db.UpdateTodoParams
	}{
		"title only": {
			req:        &todov1.UpdateTodoRequest{Id: 7, Title: proto.String("walk the dog")},
			wantParams: db.UpdateTodoParams{ID: 7, UserID: testUserID, Title: pgtype.Text{String: "walk the dog", Valid: true}},
		},
		"done only": {
			req:        &todov1.UpdateTodoRequest{Id: 7, Done: proto.Bool(false)},
			wantParams: db.UpdateTodoParams{ID: 7, UserID: testUserID, Completed: pgtype.Bool{Bool: false, Valid: true}},
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			var gotParams db.UpdateTodoParams
			svc := NewService(fakeQuerier{
				updateTodo: func(_ context.Context, arg db.UpdateTodoParams) (db.Todo, error) {
					gotParams = arg

					return db.Todo{ID: arg.ID}, nil
				},
			})

			if _, err := svc.UpdateTodo(authed(t), connect.NewRequest(tt.req)); err != nil {
				t.Fatalf("UpdateTodo() error = %v, want nil", err)
			}

			if diff := cmp.Diff(tt.wantParams, gotParams); diff != "" {
				t.Errorf("params passed to the query (-want +got):\n%s", diff)
			}
		})
	}
}

func TestServiceUpdateTodoNoFields(t *testing.T) {
	t.Parallel()

	svc := NewService(fakeQuerier{
		updateTodo: func(context.Context, db.UpdateTodoParams) (db.Todo, error) {
			t.Error("UpdateTodo query called, want the request rejected first")

			return db.Todo{}, nil
		},
	})

	res, err := svc.UpdateTodo(authed(t), connect.NewRequest(&todov1.UpdateTodoRequest{Id: 7}))
	if res != nil {
		t.Errorf("UpdateTodo() response = %v, want nil", res)
	}
	if got := connect.CodeOf(err); got != connect.CodeInvalidArgument {
		t.Errorf("UpdateTodo() code = %v, want %v", got, connect.CodeInvalidArgument)
	}
}

func TestServiceUpdateTodoInvalidID(t *testing.T) {
	t.Parallel()

	tests := map[string]int64{
		"zero":     0,
		"negative": -1,
	}

	for name, id := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			svc := NewService(fakeQuerier{
				updateTodo: func(context.Context, db.UpdateTodoParams) (db.Todo, error) {
					t.Error("UpdateTodo query called, want the request rejected first")

					return db.Todo{}, nil
				},
			})

			res, err := svc.UpdateTodo(
				authed(t),
				connect.NewRequest(&todov1.UpdateTodoRequest{Id: id, Done: proto.Bool(true)}),
			)
			if res != nil {
				t.Errorf("UpdateTodo() response = %v, want nil", res)
			}
			if got := connect.CodeOf(err); got != connect.CodeInvalidArgument {
				t.Errorf("UpdateTodo() code = %v, want %v", got, connect.CodeInvalidArgument)
			}
		})
	}
}

func TestServiceUpdateTodoBlankTitle(t *testing.T) {
	t.Parallel()

	svc := NewService(fakeQuerier{
		updateTodo: func(context.Context, db.UpdateTodoParams) (db.Todo, error) {
			t.Error("UpdateTodo query called, want the request rejected first")

			return db.Todo{}, nil
		},
	})

	_, err := svc.UpdateTodo(
		authed(t),
		connect.NewRequest(&todov1.UpdateTodoRequest{Id: 7, Title: proto.String("   ")}),
	)
	if got := connect.CodeOf(err); got != connect.CodeInvalidArgument {
		t.Errorf("UpdateTodo() code = %v, want %v", got, connect.CodeInvalidArgument)
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
				authed(t),
				connect.NewRequest(&todov1.UpdateTodoRequest{Id: 42, Done: proto.Bool(true)}),
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

	_, err := svc.UpdateTodo(
		authed(t),
		connect.NewRequest(&todov1.UpdateTodoRequest{Id: 42, Done: proto.Bool(true)}),
	)

	var connectErr *connect.Error
	if !errors.As(err, &connectErr) {
		t.Fatalf("UpdateTodo() error = %v, want a *connect.Error", err)
	}
	if diff := cmp.Diff("todo 42 not found", connectErr.Message()); diff != "" {
		t.Errorf("UpdateTodo() message (-want +got):\n%s", diff)
	}
}

// Nothing here is reachable without the authentication interceptor having
// resolved an account, so a context without one is refused before any query
// runs rather than falling back to a default owner.
func TestServiceRefusesAnUnauthenticatedContext(t *testing.T) {
	t.Parallel()

	fail := func(t *testing.T) fakeQuerier {
		t.Helper()

		return fakeQuerier{
			createTodo: func(context.Context, db.CreateTodoParams) (db.Todo, error) {
				t.Error("CreateTodo query called, want the request rejected first")

				return db.Todo{}, nil
			},
			listTodos: func(context.Context, db.ListTodosParams) ([]db.Todo, error) {
				t.Error("ListTodos query called, want the request rejected first")

				return nil, nil
			},
			updateTodo: func(context.Context, db.UpdateTodoParams) (db.Todo, error) {
				t.Error("UpdateTodo query called, want the request rejected first")

				return db.Todo{}, nil
			},
			deleteTodo: func(context.Context, db.DeleteTodoParams) (int64, error) {
				t.Error("DeleteTodo query called, want the request rejected first")

				return 0, nil
			},
		}
	}

	tests := map[string]func(context.Context, *Service) error{
		"CreateTodo": func(ctx context.Context, svc *Service) error {
			_, err := svc.CreateTodo(ctx, connect.NewRequest(&todov1.CreateTodoRequest{Title: "buy milk"}))

			return err
		},
		"ListTodos": func(ctx context.Context, svc *Service) error {
			_, err := svc.ListTodos(ctx, connect.NewRequest(&todov1.ListTodosRequest{}))

			return err
		},
		"UpdateTodo": func(ctx context.Context, svc *Service) error {
			_, err := svc.UpdateTodo(ctx, connect.NewRequest(&todov1.UpdateTodoRequest{
				Id:   7,
				Done: proto.Bool(true),
			}))

			return err
		},
		"DeleteTodo": func(ctx context.Context, svc *Service) error {
			_, err := svc.DeleteTodo(ctx, connect.NewRequest(&todov1.DeleteTodoRequest{Id: 7}))

			return err
		},
	}

	for name, call := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			err := call(t.Context(), NewService(fail(t)))
			if got := connect.CodeOf(err); got != connect.CodeUnauthenticated {
				t.Errorf("%s() code = %v, want %v", name, got, connect.CodeUnauthenticated)
			}
		})
	}
}

func TestServiceDeleteTodo(t *testing.T) {
	t.Parallel()

	var gotParams db.DeleteTodoParams
	svc := NewService(fakeQuerier{
		deleteTodo: func(_ context.Context, arg db.DeleteTodoParams) (int64, error) {
			gotParams = arg

			return 1, nil
		},
	})

	res, err := svc.DeleteTodo(authed(t), connect.NewRequest(&todov1.DeleteTodoRequest{Id: 7}))
	if err != nil {
		t.Fatalf("DeleteTodo() error = %v, want nil", err)
	}
	if res == nil {
		t.Fatal("DeleteTodo() response = nil, want non-nil")
	}

	wantParams := db.DeleteTodoParams{ID: 7, UserID: testUserID}
	if diff := cmp.Diff(wantParams, gotParams); diff != "" {
		t.Errorf("params passed to the query (-want +got):\n%s", diff)
	}
}

func TestServiceDeleteTodoInvalidID(t *testing.T) {
	t.Parallel()

	tests := map[string]int64{
		"zero":     0,
		"negative": -1,
	}

	for name, id := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			svc := NewService(fakeQuerier{
				deleteTodo: func(context.Context, db.DeleteTodoParams) (int64, error) {
					t.Error("DeleteTodo query called, want the request rejected first")

					return 0, nil
				},
			})

			res, err := svc.DeleteTodo(authed(t), connect.NewRequest(&todov1.DeleteTodoRequest{Id: id}))
			if res != nil {
				t.Errorf("DeleteTodo() response = %v, want nil", res)
			}
			if got := connect.CodeOf(err); got != connect.CodeInvalidArgument {
				t.Errorf("DeleteTodo() code = %v, want %v", got, connect.CodeInvalidArgument)
			}
		})
	}
}

func TestServiceDeleteTodoErrors(t *testing.T) {
	t.Parallel()

	tests := map[string]struct {
		deleted  int64
		queryErr error
		wantCode connect.Code
	}{
		"unknown id": {
			deleted:  0,
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
				deleteTodo: func(context.Context, db.DeleteTodoParams) (int64, error) {
					return tt.deleted, tt.queryErr
				},
			})

			res, err := svc.DeleteTodo(authed(t), connect.NewRequest(&todov1.DeleteTodoRequest{Id: 42}))
			if res != nil {
				t.Errorf("DeleteTodo() response = %v, want nil", res)
			}
			if got := connect.CodeOf(err); got != tt.wantCode {
				t.Errorf("DeleteTodo() code = %v, want %v", got, tt.wantCode)
			}
			if tt.wantCode == connect.CodeInternal {
				assertNoLeak(t, err)
			}
		})
	}
}

func TestServiceDeleteTodoNotFoundMentionsID(t *testing.T) {
	t.Parallel()

	svc := NewService(fakeQuerier{
		deleteTodo: func(context.Context, db.DeleteTodoParams) (int64, error) {
			return 0, nil
		},
	})

	_, err := svc.DeleteTodo(authed(t), connect.NewRequest(&todov1.DeleteTodoRequest{Id: 42}))

	var connectErr *connect.Error
	if !errors.As(err, &connectErr) {
		t.Fatalf("DeleteTodo() error = %v, want a *connect.Error", err)
	}
	if diff := cmp.Diff("todo 42 not found", connectErr.Message()); diff != "" {
		t.Errorf("DeleteTodo() message (-want +got):\n%s", diff)
	}
}
