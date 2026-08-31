-- Create "todos" table
CREATE TABLE "todos" (
  "id" bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
  "title" text NOT NULL,
  "completed" boolean NOT NULL DEFAULT false,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);
