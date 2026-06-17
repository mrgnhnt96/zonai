// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Built-in operations and rules for framework-managed SQLite tables.
//
// These are merged into generated `db_operations` / `db_rules` /
// `db_rate_limit` / `db_extensions` / `db_crons` executables; app authors do not add files
// for them under `lib/src/operations`, `lib/src/rules`, `lib/src/rate_limit`,
// `lib/src/extensions`, or `lib/src/crons`.
//
// Regenerate: dart run tool/generate_internal_db_artifacts.dart


import 'package:raindrop/raindrop.dart' show Schema;
import 'package:zonai_schema/src/internal/tables/abusers_table.dart' as _schema_abusers;
import 'package:zonai_schema/src/internal/tables/auth_challenge_table.dart' as _schema_authChallenges;
import 'package:zonai_schema/src/internal/tables/crons_table.dart' as _schema_crons;
import 'package:zonai_schema/src/internal/tables/jwt_table.dart' as _schema_jwts;
import 'package:zonai_schema/src/internal/tables/logs_table.dart' as _schema_logs;
import 'package:zonai_schema/src/internal/tables/photos_table.dart' as _schema_photos;
import 'package:zonai_schema/src/internal/tables/rate_limit_table.dart' as _schema_rateLimits;

abstract final class InternalDbArtifacts {
  static const operations = <({String importPath, String alias})>[
    (
      importPath:
          'package:zonai_schema/src/internal/operations/abuser_operations.dart',
      alias: 'zonai_internal_abuser_operations',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/operations/auth_challenge_operations.dart',
      alias: 'zonai_internal_auth_challenge_operations',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/operations/cron_operations.dart',
      alias: 'zonai_internal_cron_operations',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/operations/jwt_operations.dart',
      alias: 'zonai_internal_jwt_operations',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/operations/log_operations.dart',
      alias: 'zonai_internal_log_operations',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/operations/photo_operations.dart',
      alias: 'zonai_internal_photo_operations',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/operations/raindrop_migrations_operations.dart',
      alias: 'zonai_internal_raindrop_migrations_operations',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/operations/rate_limit_operations.dart',
      alias: 'zonai_internal_rate_limit_operations',
    ),
  ];

  static const rules = <({String importPath, String alias})>[
    (
      importPath:
          'package:zonai_schema/src/internal/rules/abuser_row_rules.dart',
      alias: 'zonai_internal_abuser_row_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/abuser_table_rules.dart',
      alias: 'zonai_internal_abuser_table_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/auth_challenge_row_rules.dart',
      alias: 'zonai_internal_auth_challenge_row_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/auth_challenge_table_rules.dart',
      alias: 'zonai_internal_auth_challenge_table_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/cron_row_rules.dart',
      alias: 'zonai_internal_cron_row_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/cron_table_rules.dart',
      alias: 'zonai_internal_cron_table_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/jwt_row_rules.dart',
      alias: 'zonai_internal_jwt_row_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/jwt_table_rules.dart',
      alias: 'zonai_internal_jwt_table_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/log_row_rules.dart',
      alias: 'zonai_internal_log_row_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/log_table_rules.dart',
      alias: 'zonai_internal_log_table_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/photo_row_rules.dart',
      alias: 'zonai_internal_photo_row_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/photo_table_rules.dart',
      alias: 'zonai_internal_photo_table_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/raindrop_migrations_row_rules.dart',
      alias: 'zonai_internal_raindrop_migrations_row_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/raindrop_migrations_table_rules.dart',
      alias: 'zonai_internal_raindrop_migrations_table_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/rate_limit_row_rules.dart',
      alias: 'zonai_internal_rate_limit_row_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/rate_limit_table_rules.dart',
      alias: 'zonai_internal_rate_limit_table_rules',
    ),
  ];

  static const rateLimits = <({String importPath, String alias})>[
  ];

  static const extensions = <({String importPath, String alias})>[
  ];

  static const crons = <({String importPath, String alias})>[
    (
      importPath:
          'package:zonai_schema/src/internal/crons/cleanup_auth_challenges_cron.dart',
      alias: 'zonai_internal_cleanup_auth_challenges_cron',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/crons/cleanup_cron_entries_cron.dart',
      alias: 'zonai_internal_cleanup_cron_entries_cron',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/crons/cleanup_logs_cron.dart',
      alias: 'zonai_internal_cleanup_logs_cron',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/crons/cleanup_unreferenced_photos_cron.dart',
      alias: 'zonai_internal_cleanup_unreferenced_photos_cron',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/crons/delete_expired_jwts_cron.dart',
      alias: 'zonai_internal_delete_expired_jwts_cron',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/crons/delete_old_rate_limits_cron.dart',
      alias: 'zonai_internal_delete_old_rate_limits_cron',
    ),
  ];

  /// Framework-managed tables (import path, top-level getter, table).
  static const tables = <({String importPath, String getter, String tableName})>[
    (
      importPath:
          'package:zonai_schema/src/internal/tables/abusers_table.dart',
      getter: 'abusers',
      tableName: '_abusers',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/tables/auth_challenge_table.dart',
      getter: 'authChallenges',
      tableName: '_auth_challenges',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/tables/crons_table.dart',
      getter: 'crons',
      tableName: '_cron_jobs',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/tables/jwt_table.dart',
      getter: 'jwts',
      tableName: '_jwt',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/tables/logs_table.dart',
      getter: 'logs',
      tableName: '_log',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/tables/photos_table.dart',
      getter: 'photos',
      tableName: '_photos',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/tables/rate_limit_table.dart',
      getter: 'rateLimits',
      tableName: '_rate_limit',
    ),
  ];

  /// Table schemas ensured on database open (migrations apply changes).
  static final schemas = <Schema<Object?>>[
    _schema_abusers.abusers,
    _schema_authChallenges.authChallenges,
    _schema_crons.crons,
    _schema_jwts.jwts,
    _schema_logs.logs,
    _schema_photos.photos,
    _schema_rateLimits.rateLimits,
  ];

  /// SQLite table names managed by the framework (not user schemas).
  static const tableNames = {'_abusers', '_auth_challenges', '_cron_jobs', '_jwt', '_log', '_photos', '_rate_limit'};
}

