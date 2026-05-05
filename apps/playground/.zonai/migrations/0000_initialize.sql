CREATE TABLE "items" (
  "id" TEXT PRIMARY KEY,
  "body" TEXT NOT NULL,
  "description" TEXT,
  "status" INTEGER,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER
);