CREATE TABLE IF NOT EXISTS "_push_jobs" (
  "id" TEXT PRIMARY KEY,
  "message" TEXT NOT NULL,
  "target_table" TEXT NOT NULL,
  "target_column" TEXT NOT NULL,
  "where_json" TEXT,
  "cursor" TEXT,
  "status" TEXT NOT NULL,
  "delivered" INTEGER NOT NULL DEFAULT 0,
  "permanently_rejected" INTEGER NOT NULL DEFAULT 0,
  "transiently_failed" INTEGER NOT NULL DEFAULT 0,
  "error" TEXT,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "push_job_id_unique" ON "_push_jobs" ("id");

CREATE INDEX IF NOT EXISTS "push_job_status_created_index" ON "_push_jobs" ("status", "created_at");