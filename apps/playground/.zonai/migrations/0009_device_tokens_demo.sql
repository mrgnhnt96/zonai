CREATE TABLE "device_tokens" (
  "id" TEXT PRIMARY KEY,
  "user_id" TEXT NOT NULL,
  "label" TEXT NOT NULL,
  "token" TEXT,
  "platform" TEXT NOT NULL,
  "created_at" INTEGER NOT NULL
);

PRAGMA defer_foreign_keys = ON;
CREATE TABLE "__new_users" (
  "id" TEXT PRIMARY KEY,
  "name" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "is_verified" INTEGER NOT NULL,
  "password" TEXT NOT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER
);
INSERT INTO "__new_users" ("id", "name", "email", "is_verified", "password", "created_at", "updated_at") SELECT "id", "name", "email", "is_verified", "password", "created_at", "updated_at" FROM "users";
DROP TABLE "users";
ALTER TABLE "__new_users" RENAME TO "users";
CREATE UNIQUE INDEX "users.id_unique" ON "users" ("id");