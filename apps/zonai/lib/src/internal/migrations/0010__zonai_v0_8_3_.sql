CREATE TABLE IF NOT EXISTS "_password_reset_requirements" (
  "id" TEXT PRIMARY KEY,
  "table" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "reason" TEXT NOT NULL,
  "created_by" TEXT,
  "created_at" INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "password_reset_requirement_account_unique" ON "_password_reset_requirements" ("table", "user_id");