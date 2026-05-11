CREATE TABLE "items_raindrop_rebuild" (
  "id" TEXT PRIMARY KEY,
  "body" TEXT NOT NULL,
  "description" TEXT,
  "status" INTEGER,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER
);
INSERT INTO "items_raindrop_rebuild" SELECT * FROM "items";
DROP TABLE "items";
ALTER TABLE "items_raindrop_rebuild" RENAME TO "items";

CREATE TABLE "users_raindrop_rebuild" (
  "email" TEXT NOT NULL,
  "password" TEXT NOT NULL,
  "id" TEXT PRIMARY KEY,
  "name" TEXT NOT NULL,
  "deleted_at" INTEGER
);
INSERT INTO "users_raindrop_rebuild" SELECT * FROM "users";
DROP TABLE "users";
ALTER TABLE "users_raindrop_rebuild" RENAME TO "users";

ALTER TABLE "users" RENAME COLUMN "deleted_at" TO "updated_at";

ALTER TABLE "users" ADD COLUMN "created_at" INTEGER NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX "users.id_unique" ON "users" ("id");