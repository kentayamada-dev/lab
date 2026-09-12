-- Opening a session is also when the account's finished ones are dropped.
-- Nothing goes looking for an expired row otherwise, since verifying reads the
-- single row a token names, so without this the table would only ever grow.
-- name: CreateSession :one
WITH swept AS (
  DELETE FROM sessions
  WHERE user_id = sqlc.arg(user_id) AND expires_at <= now()
)
INSERT INTO sessions (user_id, expires_at)
VALUES (sqlc.arg(user_id), sqlc.arg(expires_at))
RETURNING *;

-- The account is matched as well as the session, so a token whose two claims
-- disagree names nothing. The token carries its own expiry and is checked
-- against it before this runs, which is why the row's is not read here.
--
-- The join reaches the account itself to find out whether it is still open.
-- Closing deletes these rows in the same statement that records it
-- (api/queries/users.sql), so there should be nothing for this to catch; it is
-- here because the alternative is that any session which does survive keeps
-- serving an account that no longer exists, and the row is already being read.
-- name: SessionExists :one
SELECT EXISTS (
  SELECT 1 FROM sessions
  JOIN users ON users.id = sessions.user_id
  WHERE sessions.id = sqlc.arg(id)
    AND sessions.user_id = sqlc.arg(user_id)
    AND users.deleted_at IS NULL
) AS session_exists;

-- The account is named alongside the session, as everywhere else a row is
-- reached by id (api/queries/todos.sql). Its only caller takes both out of one
-- verified token, so the two cannot disagree there; the condition is what keeps
-- a caller that came by the id some other way from reaching a session that is
-- not its own.
-- name: DeleteSession :exec
DELETE FROM sessions
WHERE id = sqlc.arg(id) AND user_id = sqlc.arg(user_id);
