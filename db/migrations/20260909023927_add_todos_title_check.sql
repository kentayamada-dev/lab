-- Modify "todos" table
ALTER TABLE "todos" ADD CONSTRAINT "todos_title_valid" CHECK ((btrim(title) <> ''::text) AND (char_length(title) <= 1000));
