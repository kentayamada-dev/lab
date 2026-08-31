package todo

import (
	"example/app/gen/db"
	todov1 "example/app/gen/go/todo/v1"
)

func toProtoTodo(t db.Todo) *todov1.Todo {
	return &todov1.Todo{
		Id:    t.ID,
		Title: t.Title,
		Done:  t.Completed,
	}
}
