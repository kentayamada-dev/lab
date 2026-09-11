CREATE TABLE users (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- The API lower-cases an address before it gets here, so plain equality is
  -- already the case-insensitive comparison this unique constraint is meant to
  -- be, without citext.
  email text NOT NULL UNIQUE,
  -- A bcrypt hash, never the password itself.
  password_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Minimal backstop, as on todos.title below: what an address has to look
  -- like is settled by the API, and only the degenerate cases are rejected
  -- here. 254 is the longest address that can be delivered to.
  CONSTRAINT users_email_valid CHECK (btrim(email) <> '' AND char_length(email) <= 254)
);

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
