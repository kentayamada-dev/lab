// Package todo implements the TodoService Connect handlers.
package todo

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"unicode/utf8"

	"connectrpc.com/connect"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"example/app/gen/db"
	todov1 "example/app/gen/go/todo/v1"
)

// maxTitleLen bounds the stored title in runes; the text column has no limit
// of its own.
const maxTitleLen = 1000

type Querier interface {
	CreateTodo(ctx context.Context, title string) (db.Todo, error)
	ListTodos(ctx context.Context) ([]db.Todo, error)
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
	rows, err := s.queries.ListTodos(ctx)
	if err != nil {
		return nil, internalError("listing todos", err)
	}

	todos := make([]*todov1.Todo, 0, len(rows))
	for _, t := range rows {
		todos = append(todos, toProtoTodo(t))
	}

	return connect.NewResponse(&todov1.ListTodosResponse{Todos: todos}), nil
}

func (s *Service) UpdateTodo(
	ctx context.Context,
	req *connect.Request[todov1.UpdateTodoRequest],
) (*connect.Response[todov1.UpdateTodoResponse], error) {
	params := db.UpdateTodoParams{
		ID:        req.Msg.Id,
		Completed: req.Msg.Done,
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
