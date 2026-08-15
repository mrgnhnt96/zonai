CREATE TABLE IF NOT EXISTS "_oauth_identities" (
  "id" TEXT PRIMARY KEY,
  "table" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "subject" TEXT NOT NULL,
  "email" TEXT,
  "created_at" INTEGER NOT NULL,
  "last_login_at" INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "oauth_identities_lookup_unique" ON "_oauth_identities" ("table", "provider", "subject");