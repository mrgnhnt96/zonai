// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Embedded internal-table migrations applied at runtime via [InternalDbMigrate].
//
// Regenerate SQL: dart run tool/generate_internal_db_artifacts.dart --migrate -n <name>
// Resync this file: dart run tool/generate_internal_db_artifacts.dart --sync-migrations-dart


import 'package:raindrop/raindrop.dart';

/// Versioned SQL for framework-managed SQLite tables (`0000_internal_*`, …).
final internalDbMigrations = [
  const Migration('0000_internal_initial', '''
CREATE TABLE IF NOT EXISTS "_auth_challenges" (
  "can_consume" INTEGER NOT NULL,
  "consumed_at" INTEGER,
  "created_at" INTEGER NOT NULL,
  "expires_at" INTEGER NOT NULL,
  "id" TEXT PRIMARY KEY,
  "metadata" TEXT,
  "secret_hash" TEXT NOT NULL,
  "table" TEXT NOT NULL,
  "target" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "user_id" TEXT
);

CREATE TABLE IF NOT EXISTS "_jwt" (
  "expires_at" INTEGER NOT NULL DEFAULT 0,
  "id" TEXT PRIMARY KEY,
  "user_id" TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "_log" (
  "error" TEXT,
  "id" TEXT PRIMARY KEY,
  "level" TEXT NOT NULL,
  "message" TEXT NOT NULL,
  "timestamp" INTEGER NOT NULL,
  "trace_id" TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "_photos" (
  "created_at" INTEGER NOT NULL,
  "extension" TEXT NOT NULL,
  "id" TEXT PRIMARY KEY,
  "owner_collection" TEXT NOT NULL,
  "owner_id" TEXT NOT NULL,
  "path" TEXT NOT NULL,
  "table" TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "_rate_limit" (
  "client_ip" TEXT NOT NULL,
  "count" INTEGER NOT NULL,
  "id" TEXT PRIMARY KEY,
  "operation" TEXT NOT NULL,
  "table" TEXT NOT NULL,
  "window_start" INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS "auth_challenges_consumed_unique" ON "_auth_challenges" ("can_consume");

CREATE INDEX IF NOT EXISTS "auth_challenges_target_collection_unique" ON "_auth_challenges" ("target", "table");

CREATE UNIQUE INDEX IF NOT EXISTS "jwt_id_unique" ON "_jwt" ("id");

CREATE UNIQUE INDEX IF NOT EXISTS "log_id_unique" ON "_log" ("id");

CREATE INDEX IF NOT EXISTS "log_level_timestamp_index" ON "_log" ("level", "timestamp");

CREATE UNIQUE INDEX IF NOT EXISTS "rate_limit_bucket_unique" ON "_rate_limit" ("client_ip", "table", "operation");'''),
];

