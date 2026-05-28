CREATE TABLE IF NOT EXISTS "_cron_jobs" (
  "completed" INTEGER,
  "error" TEXT,
  "failed" INTEGER,
  "id" TEXT PRIMARY KEY,
  "name" TEXT NOT NULL,
  "stack_trace" TEXT,
  "started" INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS "cron_incomplete_index" ON "_cron_jobs" ("name", "completed", "failed");

CREATE INDEX IF NOT EXISTS "cron_name_index" ON "_cron_jobs" ("name");