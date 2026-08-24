CREATE TABLE IF NOT EXISTS "_api_tokens" (
  "id" TEXT PRIMARY KEY,
  "name" TEXT NOT NULL,
  "token_hash" TEXT NOT NULL,
  "token_prefix" TEXT NOT NULL,
  "scope" TEXT NOT NULL,
  "claims" TEXT NOT NULL,
  "bound_table" TEXT,
  "bound_user_id" TEXT,
  "expires_at" INTEGER,
  "revoked_at" INTEGER,
  "created_at" INTEGER NOT NULL,
  "created_by" TEXT NOT NULL,
  "last_used_at" INTEGER
);

CREATE UNIQUE INDEX IF NOT EXISTS "api_token_id_unique" ON "_api_tokens" ("id");

CREATE UNIQUE INDEX IF NOT EXISTS "api_token_hash_unique" ON "_api_tokens" ("token_hash");