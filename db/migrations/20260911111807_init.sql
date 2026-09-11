-- Create "users" table
CREATE TABLE "users" ("id" bigint NOT NULL GENERATED ALWAYS AS IDENTITY, "email" text NOT NULL, "password_hash" text NOT NULL, "created_at" timestamptz NOT NULL DEFAULT now(), PRIMARY KEY ("id"), CONSTRAINT "users_email_key" UNIQUE ("email"), CONSTRAINT "users_email_valid" CHECK ((btrim(email) <> ''::text) AND (char_length(email) <= 254)));
-- Create "todos" table
CREATE TABLE "todos" ("id" bigint NOT NULL GENERATED ALWAYS AS IDENTITY, "user_id" bigint NOT NULL, "title" text NOT NULL, "completed" boolean NOT NULL DEFAULT false, "created_at" timestamptz NOT NULL DEFAULT now(), PRIMARY KEY ("id"), CONSTRAINT "todos_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON UPDATE NO ACTION ON DELETE CASCADE, CONSTRAINT "todos_title_valid" CHECK ((btrim(title) <> ''::text) AND (char_length(title) <= 1000)));
-- Create index "todos_user_id_id_idx" to table: "todos"
CREATE INDEX "todos_user_id_id_idx" ON "todos" ("user_id", "id");
