CREATE TABLE todos (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title text NOT NULL,
  completed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Minimal backstop: titles reach this table already trimmed by the API, so
  -- the check only has to reject the degenerate cases. btrim strips the space
  -- alone, so a title made of other whitespace (a tab, U+3000) still passes.
  CONSTRAINT todos_title_valid CHECK (btrim(title) <> '' AND char_length(title) <= 1000)
);
