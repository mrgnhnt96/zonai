CREATE TABLE "authors" (
  "created_at" INTEGER NOT NULL,
  "id" TEXT PRIMARY KEY,
  "name" TEXT NOT NULL,
  "updated_at" INTEGER
);

CREATE TABLE "posts" (
  "author_id" TEXT NOT NULL REFERENCES "authors"("id") ON DELETE CASCADE,
  "body" TEXT,
  "created_at" INTEGER NOT NULL,
  "id" TEXT PRIMARY KEY,
  "title" TEXT NOT NULL,
  "updated_at" INTEGER
);