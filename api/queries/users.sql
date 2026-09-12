-- name: CreateUser :one
INSERT INTO users (email, password_hash)
VALUES ($1, $2)
RETURNING *;

-- A closed account is not an account: the condition is what refuses it a
-- login rather than a tidying detail. It never has to choose between rows, the
-- address staying with the closed one until the purge erases it
-- (api/schema.sql).
-- name: GetUserByEmail :one
SELECT * FROM users
WHERE email = $1 AND deleted_at IS NULL;

-- name: GetUserByID :one
SELECT * FROM users
WHERE id = $1 AND deleted_at IS NULL;

-- Closing the account and ending its sessions is one statement because the two
-- cannot be allowed to come apart: a row marked closed whose sessions survived
-- would go on being served, the session lookup having no reason to read this
-- table twice (api/queries/sessions.sql). The sessions go by what the update
-- returned rather than by the same id, so an account that was already closed
-- takes nothing with it.
--
-- The cast is what sqlc needs: a parameter inside a CTE is one it otherwise
-- reads as nullable, and the generated signature would take a pgtype.Int8
-- where every other query in here takes the id itself.
-- name: CloseAccount :one
WITH closed AS (
  UPDATE users
  SET deleted_at = now()
  WHERE id = sqlc.arg(id)::bigint AND deleted_at IS NULL
  RETURNING *
), ended AS (
  DELETE FROM sessions
  WHERE user_id IN (SELECT id FROM closed)
)
SELECT * FROM closed;

-- Erases the accounts closed long enough ago, taking their todos with them
-- through the foreign keys. This is the only thing that deletes a user row, so
-- it is also the only thing that frees the storage a closed account still
-- occupies (api/cmd/purge).
-- name: PurgeClosedAccounts :execrows
DELETE FROM users
WHERE deleted_at IS NOT NULL AND deleted_at <= sqlc.arg(closed_before);
