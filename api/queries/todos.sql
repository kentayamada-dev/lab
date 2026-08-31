-- name: CreateTodo :one
INSERT INTO todos (title)
VALUES ($1)
RETURNING *;

-- name: ListTodos :many
SELECT * FROM todos
ORDER BY id;

-- name: UpdateTodo :one
UPDATE todos
SET completed = sqlc.arg(completed), title = coalesce(sqlc.narg(title), title)
WHERE id = sqlc.arg(id)
RETURNING *;

-- name: DeleteTodo :execrows
DELETE FROM todos
WHERE id = $1;
