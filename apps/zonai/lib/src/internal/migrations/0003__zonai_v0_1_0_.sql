CREATE TABLE IF NOT EXISTS "_abusers" (
  "black_listed" INTEGER NOT NULL,
  "blocked_until" INTEGER,
  "created_at" INTEGER NOT NULL,
  "id" TEXT PRIMARY KEY,
  "ip" TEXT NOT NULL,
  "report" TEXT NOT NULL,
  "updated_at" INTEGER
);