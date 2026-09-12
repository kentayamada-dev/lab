-- Create "sessions" table
CREATE TABLE "sessions" ("id" bigint NOT NULL GENERATED ALWAYS AS IDENTITY, "user_id" bigint NOT NULL, "expires_at" timestamptz NOT NULL, "created_at" timestamptz NOT NULL DEFAULT now(), PRIMARY KEY ("id"), CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON UPDATE NO ACTION ON DELETE CASCADE);
-- Create index "sessions_user_id_idx" to table: "sessions"
CREATE INDEX "sessions_user_id_idx" ON "sessions" ("user_id");
