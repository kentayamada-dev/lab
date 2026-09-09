// Package todo implements the TodoService Connect handlers.
package todo

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strconv"
	"strings"
	"unicode/utf8"

	"connectrpc.com/connect"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"example/app/gen/db"
	todov1 "example/app/gen/go/todo/v1"
)

const (
	// maxTitleLen bounds the stored title in runes; the text column has no
	// limit of its own.
	maxTitleLen = 1000
	// defaultPageSize is the page size used when a request does not ask for
	// one.
	defaultPageSize = 50
	// maxPageSize bounds how many todos one response can carry.
	maxPageSize = 100
)

type Querier interface {
	CreateTodo(ctx context.Context, title string) (db.Todo, error)
	ListTodos(ctx context.Context, arg db.ListTodosParams) ([]db.Todo, error)
	UpdateTodo(ctx context.Context, arg db.UpdateTodoParams) (db.Todo, error)
	DeleteTodo(ctx context.Context, id int64) (int64, error)
}

type Service struct {
	queries Querier
}

func NewService(queries Querier) *Service {
	return &Service{queries: queries}
}

// internalError logs the cause and returns a generic error, keeping details
// such as database messages out of the response.
func internalError(op string, err error) *connect.Error {
	log.Printf("%s: %v", op, err)

	return connect.NewError(connect.CodeInternal, errors.New("internal error"))
}

// validTitle trims the raw title and rejects a blank or overlong result. The
// proto fields declare the same rules, enforced by the server's validate
// interceptor; the check here keeps the service safe on its own.
func validTitle(raw string) (string, error) {
	title := strings.TrimSpace(raw)
	if title == "" {
		return "", connect.NewError(
			connect.CodeInvalidArgument,
			errors.New("title must not be blank"),
		)
	}
	if utf8.RuneCountInString(title) > maxTitleLen {
		return "", connect.NewError(
			connect.CodeInvalidArgument,
			fmt.Errorf("title must be at most %d characters", maxTitleLen),
		)
	}

	return title, nil
}

// resolvePageSize resolves the requested page size. The proto field declares
// the same bounds, enforced by the server's validate interceptor; the check
// here keeps the service safe on its own.
func resolvePageSize(requested int32) (int32, error) {
	switch {
	case requested < 0:
		return 0, connect.NewError(
			connect.CodeInvalidArgument,
			errors.New("page_size must not be negative"),
		)
	case requested == 0:
		return defaultPageSize, nil
	case requested > maxPageSize:
		return 0, connect.NewError(
			connect.CodeInvalidArgument,
			fmt.Errorf("page_size must be at most %d", maxPageSize),
		)
	}

	return requested, nil
}

// decodePageToken reads the id the previous page ended on. The token is opaque
// to clients, so anything the service did not hand out is rejected instead of
// being read as a request for the first page.
func decodePageToken(token string) (int64, error) {
	if token == "" {
		return 0, nil
	}

	after, err := strconv.ParseInt(token, 10, 64)
	if err != nil || after < 1 {
		return 0, connect.NewError(
			connect.CodeInvalidArgument,
			errors.New("page_token is not a valid token"),
		)
	}

	return after, nil
}

// validID rejects an id no todo can have: the identity column starts at 1. The
// proto fields declare the same rule, enforced by the server's validate
// interceptor; the check here keeps the service safe on its own.
func validID(id int64) error {
	if id < 1 {
		return connect.NewError(
			connect.CodeInvalidArgument,
			errors.New("id must be greater than 0"),
		)
	}

	return nil
}

func (s *Service) CreateTodo(
	ctx context.Context,
	req *connect.Request[todov1.CreateTodoRequest],
) (*connect.Response[todov1.CreateTodoResponse], error) {
	title, err := validTitle(req.Msg.Title)
	if err != nil {
		return nil, err
	}

	t, err := s.queries.CreateTodo(ctx, title)
	if err != nil {
		return nil, internalError("creating todo", err)
	}

	return connect.NewResponse(&todov1.CreateTodoResponse{Todo: toProtoTodo(t)}), nil
}

func (s *Service) ListTodos(
	ctx context.Context,
	req *connect.Request[todov1.ListTodosRequest],
) (*connect.Response[todov1.ListTodosResponse], error) {
	size, err := resolvePageSize(req.Msg.GetPageSize())
	if err != nil {
		return nil, err
	}
	after, err := decodePageToken(req.Msg.GetPageToken())
	if err != nil {
		return nil, err
	}

	// Asking for one row beyond the page answers "is there a next page?"
	// without a second query. The extra row is dropped below.
	rows, err := s.queries.ListTodos(ctx, db.ListTodosParams{
		AfterID:  after,
		PageSize: int64(size) + 1,
	})
	if err != nil {
		return nil, internalError("listing todos", err)
	}

	var nextPageToken string
	if len(rows) > int(size) {
		rows = rows[:size]
		nextPageToken = strconv.FormatInt(rows[len(rows)-1].ID, 10)
	}

	todos := make([]*todov1.Todo, 0, len(rows))
	for _, t := range rows {
		todos = append(todos, toProtoTodo(t))
	}

	return connect.NewResponse(&todov1.ListTodosResponse{
		Todos:         todos,
		NextPageToken: nextPageToken,
	}), nil
}

func (s *Service) UpdateTodo(
	ctx context.Context,
	req *connect.Request[todov1.UpdateTodoRequest],
) (*connect.Response[todov1.UpdateTodoResponse], error) {
	if err := validID(req.Msg.Id); err != nil {
		return nil, err
	}

	// The query coalesces absent fields to the stored value, so a request
	// carrying neither would rewrite the row with what it already holds. It is
	// rejected rather than served as a disguised read.
	if req.Msg.Done == nil && req.Msg.Title == nil {
		return nil, connect.NewError(
			connect.CodeInvalidArgument,
			errors.New("at least one of done or title must be present"),
		)
	}

	params := db.UpdateTodoParams{ID: req.Msg.Id}
	if req.Msg.Done != nil {
		params.Completed = pgtype.Bool{Bool: req.Msg.GetDone(), Valid: true}
	}
	if req.Msg.Title != nil {
		title, err := validTitle(req.Msg.GetTitle())
		if err != nil {
			return nil, err
		}
		params.Title = pgtype.Text{String: title, Valid: true}
	}

	t, err := s.queries.UpdateTodo(ctx, params)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, connect.NewError(
			connect.CodeNotFound,
			fmt.Errorf("todo %d not found", req.Msg.Id),
		)
	}
	if err != nil {
		return nil, internalError("updating todo", err)
	}

	return connect.NewResponse(&todov1.UpdateTodoResponse{Todo: toProtoTodo(t)}), nil
}

func (s *Service) DeleteTodo(
	ctx context.Context,
	req *connect.Request[todov1.DeleteTodoRequest],
) (*connect.Response[todov1.DeleteTodoResponse], error) {
	if err := validID(req.Msg.Id); err != nil {
		return nil, err
	}

	deleted, err := s.queries.DeleteTodo(ctx, req.Msg.Id)
	if err != nil {
		return nil, internalError("deleting todo", err)
	}
	if deleted == 0 {
		return nil, connect.NewError(
			connect.CodeNotFound,
			fmt.Errorf("todo %d not found", req.Msg.Id),
		)
	}

	return connect.NewResponse(&todov1.DeleteTodoResponse{}), nil
}
