-- name: CreateTodo :one
INSERT INTO todos (title)
VALUES ($1)
RETURNING *;

-- name: ListTodos :many
SELECT * FROM todos
ORDER BY id;

-- name: UpdateTodo :one
UPDATE todos
SET completed = $2
WHERE id = $1
RETURNING *;
