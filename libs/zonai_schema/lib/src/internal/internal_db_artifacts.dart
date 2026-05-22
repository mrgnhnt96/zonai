// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Built-in operations and rules for framework-managed SQLite tables.
//
// These are merged into generated `db_operations` / `db_rules` /
// `db_rate_limit` executables; app authors do not add files for them under
// `lib/src/operations`, `lib/src/rules`, or `lib/src/rate_limit`.
//
// Regenerate: dart run tool/generate_internal_db_artifacts.dart


import 'package:raindrop/raindrop.dart' show Schema;
import 'package:zonai_schema/src/internal/auth_challenge_collection.dart' as _schema_authChallenges;
import 'package:zonai_schema/src/internal/jwt_collection.dart' as _schema_jwts;
import 'package:zonai_schema/src/internal/raindrop_migrations_collection.dart' as _schema_raindropMigrations;
import 'package:zonai_schema/src/internal/rate_limit_collection.dart' as _schema_rateLimits;

abstract final class InternalDbArtifacts {
  static const operations = <({String importPath, String alias})>[
    (
      importPath:
          'package:zonai_schema/src/internal/operations/auth_challenge_operations.dart',
      alias: 'zonai_internal_auth_challenge_operations',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/operations/jwt_operations.dart',
      alias: 'zonai_internal_jwt_operations',
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
          'package:zonai_schema/src/internal/rules/auth_challenge_collection_rules.dart',
      alias: 'zonai_internal_auth_challenge_collection_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/auth_challenge_record_rules.dart',
      alias: 'zonai_internal_auth_challenge_record_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/jwt_collection_rules.dart',
      alias: 'zonai_internal_jwt_collection_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/jwt_record_rules.dart',
      alias: 'zonai_internal_jwt_record_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/raindrop_migrations_collection_rules.dart',
      alias: 'zonai_internal_raindrop_migrations_collection_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/raindrop_migrations_record_rules.dart',
      alias: 'zonai_internal_raindrop_migrations_record_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/rate_limit_collection_rules.dart',
      alias: 'zonai_internal_rate_limit_collection_rules',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rules/rate_limit_record_rules.dart',
      alias: 'zonai_internal_rate_limit_record_rules',
    ),
  ];

  static const rateLimits = <({String importPath, String alias})>[
  ];

  /// Framework-managed collections (import path, top-level getter, table).
  static const collections = <({String importPath, String getter, String tableName})>[
    (
      importPath:
          'package:zonai_schema/src/internal/auth_challenge_collection.dart',
      getter: 'authChallenges',
      tableName: '_auth_challenges',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/jwt_collection.dart',
      getter: 'jwts',
      tableName: '_jwt',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/raindrop_migrations_collection.dart',
      getter: 'raindropMigrations',
      tableName: '_raindrop_migrations',
    ),
    (
      importPath:
          'package:zonai_schema/src/internal/rate_limit_collection.dart',
      getter: 'rateLimits',
      tableName: '_rate_limit',
    ),
  ];

  /// Collection schemas synced to SQLite on database open.
  static final schemas = <Schema<Object?>>[
    _schema_authChallenges.authChallenges,
    _schema_jwts.jwts,
    _schema_raindropMigrations.raindropMigrations,
    _schema_rateLimits.rateLimits,
  ];

  /// SQLite table names managed by the framework (not user schemas).
  static const tableNames = {'_auth_challenges', '_jwt', '_raindrop_migrations', '_rate_limit'};
}

