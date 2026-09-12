-- Modify "users" table
ALTER TABLE "users" ADD COLUMN "deleted_at" timestamptz NULL;
-- Create index "users_deleted_at_idx" to table: "users"
CREATE INDEX "users_deleted_at_idx" ON "users" ("deleted_at") WHERE (deleted_at IS NOT NULL);
