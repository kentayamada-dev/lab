// Package todo implements the TodoService Connect handlers.
package todo

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"

	"connectrpc.com/connect"
	"github.com/jackc/pgx/v5"

	"example/app/gen/db"
	todov1 "example/app/gen/go/todo/v1"
)

type Querier interface {
	CreateTodo(ctx context.Context, title string) (db.Todo, error)
	ListTodos(ctx context.Context) ([]db.Todo, error)
	UpdateTodo(ctx context.Context, arg db.UpdateTodoParams) (db.Todo, error)
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

func (s *Service) CreateTodo(
	ctx context.Context,
	req *connect.Request[todov1.CreateTodoRequest],
) (*connect.Response[todov1.CreateTodoResponse], error) {
	if strings.TrimSpace(req.Msg.Title) == "" {
		return nil, connect.NewError(
			connect.CodeInvalidArgument,
			errors.New("title must not be blank"),
		)
	}

	t, err := s.queries.CreateTodo(ctx, req.Msg.Title)
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
	t, err := s.queries.UpdateTodo(ctx, db.UpdateTodoParams{
		ID:        req.Msg.Id,
		Completed: req.Msg.Done,
	})
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
