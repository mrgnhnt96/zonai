CREATE TABLE "cell_edit_fixtures" (
  "amount" REAL NOT NULL,
  "big_count" BLOB NOT NULL,
  "company_id" TEXT REFERENCES "companies"("id") ON DELETE SET NULL,
  "contact_email" TEXT NOT NULL,
  "count" INTEGER NOT NULL,
  "created_at" INTEGER NOT NULL,
  "flag" INTEGER NOT NULL,
  "happened_at" INTEGER NOT NULL,
  "id" TEXT PRIMARY KEY,
  "keywords" TEXT NOT NULL,
  "label" TEXT NOT NULL,
  "meta" TEXT NOT NULL,
  "payload" BLOB,
  "secret_note" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "tags" TEXT NOT NULL,
  "updated_at" INTEGER
);

ALTER TABLE "items" ADD COLUMN "image" TEXT REFERENCES "_photos"("id");