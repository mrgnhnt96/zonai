CREATE TABLE "companies" (
  "created_at" INTEGER NOT NULL,
  "id" TEXT PRIMARY KEY,
  "name" TEXT NOT NULL,
  "updated_at" INTEGER
);

ALTER TABLE "authors" ADD COLUMN "company_id" TEXT REFERENCES "companies"("id") ON DELETE SET NULL;
