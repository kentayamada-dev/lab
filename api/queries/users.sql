-- name: CreateUser :one
INSERT INTO users (email, password_hash)
VALUES ($1, $2)
RETURNING *;

-- name: GetUserByEmail :one
SELECT * FROM users
WHERE email = $1;

-- name: UserExists :one
SELECT EXISTS (
  SELECT 1 FROM users
  WHERE id = $1
) AS user_exists;
