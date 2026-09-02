package todo

import (
	"google.golang.org/protobuf/types/known/timestamppb"

	"example/app/gen/db"
	todov1 "example/app/gen/go/todo/v1"
)

func toProtoTodo(t db.Todo) *todov1.Todo {
	p := &todov1.Todo{
		Id:    t.ID,
		Title: t.Title,
		Done:  t.Completed,
	}
	if t.CreatedAt.Valid {
		p.CreatedAt = timestamppb.New(t.CreatedAt.Time)
	}

	return p
}
