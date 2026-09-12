CREATE TABLE users (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- The API lower-cases an address before it gets here, so plain equality is
  -- already the case-insensitive comparison this unique constraint is meant to
  -- be, without citext.
  email text NOT NULL UNIQUE,
  -- A bcrypt hash, never the password itself.
  password_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- When the account was closed, and null while it is open. Closing records
  -- the instant rather than deleting the row, so that an account closed by
  -- mistake can still be restored; what erases it is the purge that runs once
  -- the grace period is up (api/internal/account). The row goes on holding
  -- the address for that whole window, the unique constraint counting it like
  -- any other, so a closed account always has somewhere to be restored to.
  deleted_at timestamptz,
  -- Minimal backstop, as on todos.title below: what an address has to look
  -- like is settled by the API, and only the degenerate cases are rejected
  -- here. 254 is the longest address that can be delivered to.
  CONSTRAINT users_email_valid CHECK (btrim(email) <> '' AND char_length(email) <= 254)
);

-- The purge walks the closed accounts in the order they were closed, which is
-- a small part of the table the index keeps to itself.
CREATE INDEX users_deleted_at_idx ON users (deleted_at) WHERE deleted_at IS NOT NULL;

-- One login, which a token names alongside the account (api/internal/auth).
-- The token is signed and carries its own expiry, so a row here is not what
-- proves it genuine; it is what makes logging out mean something, since a
-- signature cannot be taken back once it is handed out.
CREATE TABLE sessions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- The cascade fires when the account is erased, which is long after it is
  -- closed; closing deletes these rows itself, in the statement that records
  -- it (api/queries/users.sql).
  user_id bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  -- The same instant the token expires at. Kept here so a finished session can
  -- be told apart from an open one without reading a token, which is what lets
  -- the rows be swept (api/queries/sessions.sql).
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Sessions are swept and revoked an account at a time.
CREATE INDEX sessions_user_id_idx ON sessions (user_id);

CREATE TABLE todos (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- Every todo belongs to the user who created it; deleting the user takes
  -- their todos with it.
  user_id bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  title text NOT NULL,
  completed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Minimal backstop: titles reach this table already trimmed by the API, so
  -- the check only has to reject the degenerate cases. btrim strips the space
  -- alone, so a title made of other whitespace (a tab, U+3000) still passes.
  CONSTRAINT todos_title_valid CHECK (btrim(title) <> '' AND char_length(title) <= 1000)
);

-- Every listing walks one user's todos in id order (api/queries/todos.sql), a
-- keyset scan the primary key alone cannot serve.
CREATE INDEX todos_user_id_id_idx ON todos (user_id, id);
