CREATE TABLE IF NOT EXISTS "_anonymous_credentials" (
  "id" TEXT PRIMARY KEY,
  "table" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "secret_hash" TEXT NOT NULL,
  "created_at" INTEGER NOT NULL,
  "last_used_at" INTEGER
);

ALTER TABLE "_jwt" ADD COLUMN "anonymous" INTEGER NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS "anonymous_credential_hash_unique" ON "_anonymous_credentials" ("secret_hash");

CREATE INDEX IF NOT EXISTS "anonymous_credential_account" ON "_anonymous_credentials" ("table", "user_id");