// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'dart:typed_data';

import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';

/// This driver's dialect.
const dialect = SQLiteDialect();

/// {@template sqlite_dialect}
/// SQL dialect for the SQLite database.
/// {@endtemplate}
class SQLiteDialect extends SqlDialect {
  /// {@macro sqlite_dialect}
  const SQLiteDialect({this.supportsUpdateDeleteLimit = false});

  /// Whether the library parses a `LIMIT` hung directly off an `UPDATE` or a
  /// `DELETE`.
  ///
  /// `SQLiteDelegate` fills this in by probing its database
  final bool supportsUpdateDeleteLimit;

  @override
  String get name => 'sqlite';

  @override
  String escapeName(String name) => '"$name"';

  @override
  String escapeParam(int number) => '\$${number + 1}';

  @override
  String escapeLiteral(Object? value) {
    return switch (value) {
      null => 'NULL',
      final bool boolean => boolean ? '1' : '0',
      final int number => '$number',
      final double number when number.isFinite => '$number',
      final String text => "'${text.replaceAll("'", "''")}'",
      final Uint8List bytes => "X'${_hex(bytes)}'",
      _ => throw ArgumentError.value(
          value,
          'value',
          'has no SQLite literal form',
        ),
    };
  }

  String _hex(Uint8List bytes) => [
        for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
      ].join();

  /// Disables foreign keys for the migration, returning whether they were on.
  ///
  /// A table rebuild follows SQLite's 12-step ALTER TABLE procedure, whose
  /// first step is exactly this. With foreign keys ON, the `DROP TABLE` in
  /// that procedure performs an implicit DELETE which fires `ON DELETE
  /// CASCADE` on referencing rows and destroys them. `defer_foreign_keys`
  /// does not help: it defers constraint *enforcement*, while cascade
  /// *actions* still run.
  ///
  /// Nothing is lost by disabling them, because [verifyMigration] runs
  /// `foreign_key_check` before the transaction commits -- violations abort
  /// the migration rather than being enforced statement by statement.
  @override
  Future<Object?> beginMigration(MigrationExecute execute) async {
    final result = await execute('PRAGMA foreign_keys');
    final wasEnabled = result.rows.isNotEmpty && result.rows.first.first == 1;
    if (wasEnabled) await execute('PRAGMA foreign_keys = OFF');
    return wasEnabled;
  }

  /// Fails the migration if it left a foreign key violation behind.
  ///
  /// This is what makes disabling enforcement in [beginMigration] safe. It
  /// runs inside the transaction, so throwing rolls the whole migration back.
  @override
  Future<void> verifyMigration(MigrationExecute execute) async {
    final result = await execute('PRAGMA foreign_key_check');
    if (result.rows.isEmpty) return;

    final violations = result.rows
        .map((row) => row.map((cell) => '$cell').join(', '))
        .join('\n  ');
    throw MigrationForeignKeyViolation(violations);
  }

  @override
  Future<void> endMigration(MigrationExecute execute, Object? state) async {
    if (state == true) await execute('PRAGMA foreign_keys = ON');
  }
}

/// {@template migration_foreign_key_violation}
/// Thrown when a migration leaves a foreign key violation behind.
///
/// Foreign keys are disabled for the duration of a migration (SQLite's
/// 12-step ALTER TABLE procedure requires it), so violations surface here, at
/// `PRAGMA foreign_key_check`, instead of statement by statement.
/// {@endtemplate}
class MigrationForeignKeyViolation implements Exception {
  /// {@macro migration_foreign_key_violation}
  const MigrationForeignKeyViolation(this.violations);

  /// The rows reported by `PRAGMA foreign_key_check`, one per line, each as
  /// `table, rowid, parent, fkid`.
  final String violations;

  @override
  String toString() => '''
MigrationForeignKeyViolation: the migration left foreign key violations, and has been rolled back. `PRAGMA foreign_key_check` reported:
  $violations''';
}
