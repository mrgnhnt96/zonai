// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Embedded internal-table migrations applied at runtime via [InternalDbMigrate].
//
// Regenerate SQL: dart run tool/generate_internal_db_artifacts.dart --migrate -n <name>
// Resync this file: dart run tool/generate_internal_db_artifacts.dart --sync-migrations-dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// Versioned SQL for framework-managed SQLite tables (`0000_internal_*`, …).
final internalDbMigrations = [
  const Migration(
    '0000_internal_initial',
    '''
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

CREATE UNIQUE INDEX IF NOT EXISTS "rate_limit_bucket_unique" ON "_rate_limit" ("client_ip", "table", "operation");''',
  ),
  const Migration('0001_internal_update', '''
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

CREATE INDEX IF NOT EXISTS "cron_name_index" ON "_cron_jobs" ("name");'''),
  const Migration(
    '0002_internal_update',
    '''
ALTER TABLE "_auth_challenges" ADD COLUMN "allowed_attempts" INTEGER NOT NULL DEFAULT 0;''',
  ),
  const Migration('0003__zonai_v0_1_0_', '''
CREATE TABLE IF NOT EXISTS "_abusers" (
  "black_listed" INTEGER NOT NULL,
  "blocked_until" INTEGER,
  "created_at" INTEGER NOT NULL,
  "id" TEXT PRIMARY KEY,
  "ip" TEXT NOT NULL,
  "report" TEXT NOT NULL,
  "updated_at" INTEGER
);'''),
  const Migration('0004_internal_add_log_props', '''
ALTER TABLE "_log" ADD COLUMN "props" TEXT;'''),
  const Migration('0005_internal_add_log_is_admin', '''
ALTER TABLE "_log" ADD COLUMN "is_admin" INTEGER NOT NULL DEFAULT 0;'''),
  const Migration(
    '0006_internal_push_jobs',
    '''
CREATE TABLE IF NOT EXISTS "_push_jobs" (
  "id" TEXT PRIMARY KEY,
  "message" TEXT NOT NULL,
  "target_table" TEXT NOT NULL,
  "target_column" TEXT NOT NULL,
  "where_json" TEXT,
  "cursor" TEXT,
  "status" TEXT NOT NULL,
  "delivered" INTEGER NOT NULL DEFAULT 0,
  "permanently_rejected" INTEGER NOT NULL DEFAULT 0,
  "transiently_failed" INTEGER NOT NULL DEFAULT 0,
  "error" TEXT,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "push_job_id_unique" ON "_push_jobs" ("id");

CREATE INDEX IF NOT EXISTS "push_job_status_created_index" ON "_push_jobs" ("status", "created_at");''',
  ),
  const Migration('0007_push_jobs_platform', '''
ALTER TABLE "_push_jobs" ADD COLUMN "platform_column" TEXT;'''),
  const Migration(
    '0008_add_oauth_identities_table',
    '''
CREATE TABLE IF NOT EXISTS "_oauth_identities" (
  "id" TEXT PRIMARY KEY,
  "table" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "subject" TEXT NOT NULL,
  "email" TEXT,
  "created_at" INTEGER NOT NULL,
  "last_login_at" INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "oauth_identities_lookup_unique" ON "_oauth_identities" ("table", "provider", "subject");''',
  ),
  const Migration(
    '0009_api_tokens',
    '''
CREATE TABLE IF NOT EXISTS "_api_tokens" (
  "id" TEXT PRIMARY KEY,
  "name" TEXT NOT NULL,
  "token_hash" TEXT NOT NULL,
  "token_prefix" TEXT NOT NULL,
  "scope" TEXT NOT NULL,
  "claims" TEXT NOT NULL,
  "bound_table" TEXT,
  "bound_user_id" TEXT,
  "expires_at" INTEGER,
  "revoked_at" INTEGER,
  "created_at" INTEGER NOT NULL,
  "created_by" TEXT NOT NULL,
  "last_used_at" INTEGER
);

CREATE UNIQUE INDEX IF NOT EXISTS "api_token_id_unique" ON "_api_tokens" ("id");

CREATE UNIQUE INDEX IF NOT EXISTS "api_token_hash_unique" ON "_api_tokens" ("token_hash");''',
  ),
  const Migration(
    '0010__zonai_v0_8_3_',
    '''
CREATE TABLE IF NOT EXISTS "_password_reset_requirements" (
  "id" TEXT PRIMARY KEY,
  "table" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "reason" TEXT NOT NULL,
  "created_by" TEXT,
  "created_at" INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "password_reset_requirement_account_unique" ON "_password_reset_requirements" ("table", "user_id");''',
  ),
];
