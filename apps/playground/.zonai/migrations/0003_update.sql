ALTER TABLE "items" ALTER COLUMN "id" SET NOT NULL;

ALTER TABLE "users" ALTER COLUMN "id" SET NOT NULL;

ALTER TABLE "users" RENAME COLUMN "deleted_at" TO "updated_at";

ALTER TABLE "users" ADD COLUMN "created_at" INTEGER NOT NULL;

CREATE UNIQUE INDEX "users.id_unique" ON "users" ("id");