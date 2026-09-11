-- name: CreateTodo :one
INSERT INTO todos (user_id, title)
VALUES ($1, $2)
RETURNING *;

-- name: ListTodos :many
SELECT * FROM todos
WHERE user_id = sqlc.arg(user_id) AND id > sqlc.arg(after_id)
ORDER BY id
LIMIT sqlc.arg(page_size);

-- A todo of another user is left alone and reported as missing, so the answer
-- says nothing about whether that id exists.
-- name: UpdateTodo :one
UPDATE todos
SET completed = coalesce(sqlc.narg(completed), completed), title = coalesce(sqlc.narg(title), title)
WHERE id = sqlc.arg(id) AND user_id = sqlc.arg(user_id)
RETURNING *;

-- name: DeleteTodo :execrows
DELETE FROM todos
WHERE id = sqlc.arg(id) AND user_id = sqlc.arg(user_id);
