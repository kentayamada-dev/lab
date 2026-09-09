CREATE TABLE todos (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title text NOT NULL,
  completed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Backstop for the rules the API enforces on the trimmed title; titles reach
  -- this table already trimmed.
  CONSTRAINT todos_title_valid CHECK (btrim(title) <> '' AND char_length(title) <= 1000)
);
