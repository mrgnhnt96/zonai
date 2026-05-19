/// Built-in operations and rules for framework-managed SQLite tables.
///
/// These are merged into generated `db_operations` / `db_rules` executables;
/// app authors do not add files for them under `lib/src/operations` or
/// `lib/src/rules`.
abstract final class InternalDbArtifacts {
  static const operations = <({String importPath, String alias})>[
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
  ];

  static const rules = <({String importPath, String alias})>[
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
  ];

  /// SQLite table names managed by the framework (not user schemas).
  static const tableNames = {'_jwt', '_raindrop_migrations'};
}
