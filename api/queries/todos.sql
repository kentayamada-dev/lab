-- name: CreateTodo :one
INSERT INTO todos (title)
VALUES ($1)
RETURNING *;

-- name: ListTodos :many
SELECT * FROM todos
WHERE id > sqlc.arg(after_id)
ORDER BY id
LIMIT sqlc.arg(page_size);

-- name: UpdateTodo :one
UPDATE todos
SET completed = coalesce(sqlc.narg(completed), completed), title = coalesce(sqlc.narg(title), title)
WHERE id = sqlc.arg(id)
RETURNING *;

-- name: DeleteTodo :execrows
DELETE FROM todos
WHERE id = $1;
