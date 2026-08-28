// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/ddl.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_dialect.dart';

/// {@template sqlite_ddl_generator}
/// DDL generator for SQLite.
/// {@endtemplate}
class SQLiteDdlGenerator extends DdlGenerator {
  /// {@macro sqlite_ddl_generator}
  const SQLiteDdlGenerator() : super(dialect: const SQLiteDialect());

  @override
  String createTable(TableInfo table) {
    final defs = [
      ...table.columns.map(_columnDefinition),
      for (final entry in table.checks.entries)
        'CONSTRAINT ${escapeName(entry.key)} CHECK (${entry.value})',
    ].join(',\n  ');
    return 'CREATE TABLE ${escapeName(table.name)} (\n  $defs\n);';
  }

  @override
  String dropTable(String tableName) {
    return 'DROP TABLE ${escapeName(tableName)};';
  }

  @override
  String alterTable(AlterTable operation) {
    final diff = TableDiff.of(operation);
    requireBackfillableAdds(operation.tableName, diff.addedColumns);
    return _isSimple(operation, diff)
        ? _simpleAlter(operation, diff)
        : _rebuild(operation, diff);
  }

  @override
  String createIndex(IndexInfo index) {
    final unique = index.isUnique ? 'UNIQUE ' : '';
    final cols = index.columns.map(escapeName).join(', ');
    final where = index.where != null ? ' WHERE ${index.where}' : '';
    return '''
CREATE ${unique}INDEX ${escapeName(index.name)} ON ${escapeName(index.tableName)} ($cols)$where;''';
  }

  @override
  String dropIndex(String indexName) {
    return 'DROP INDEX ${escapeName(indexName)};';
  }

  @override
  String getColumnType(ColumnInfo column) => column.type;

  /// Whether every change fits SQLite's ALTER whitelist.
  bool _isSimple(AlterTable operation, TableDiff diff) {
    if (diff.changesDefinitions) return false;

    for (final column in diff.addedColumns) {
      if (!_canAddColumn(column)) return false;
    }

    for (final column in diff.droppedColumns) {
      // DROP COLUMN is rejected for key columns, indexed columns, columns in
      // a CHECK, and columns referenced from elsewhere.
      if (column.primaryKey || column.foreignKey != null) return false;
      final indexed = operation.oldIndexes
          .any((index) => index.columns.contains(column.name));
      if (indexed) return false;
      if (operation.oldTable.checks.isNotEmpty) return false;
      final referenced = operation.referencedBy.any(
        (dependent) => dependent.table.columns.any(
          (c) =>
              c.foreignKey?.referencedTable == operation.tableName &&
              c.foreignKey?.referencedColumn == column.name,
        ),
      );
      if (referenced) return false;
    }

    return true;
  }

  /// Whether [column] can be appended with `ALTER TABLE ... ADD COLUMN`.
  ///
  /// SQLite accepts far more here than a nullable column with no default --
  /// see https://sqlite.org/lang_altertable.html#altertabaddcol. It refuses
  /// only: a PRIMARY KEY or UNIQUE column; a NOT NULL column without a
  /// non-null default (existing rows would have no value); a non-constant
  /// default, meaning `CURRENT_TIME`/`CURRENT_DATE`/`CURRENT_TIMESTAMP` or a
  /// parenthesized expression; a `REFERENCES` column whose default is not
  /// NULL; and a generated `STORED` column.
  ///
  /// UNIQUE and generated columns are not representable on [ColumnInfo], so
  /// there is nothing to test for them here. A UNIQUE *index* added over the
  /// new column is a separate `CREATE UNIQUE INDEX`, which SQLite allows.
  bool _canAddColumn(ColumnInfo column) {
    if (column.primaryKey || column.autoIncrement) return false;

    final defaultValue = column.defaultValue;
    final hasNonNullDefault =
        defaultValue != null && !_isNullLiteral(defaultValue);

    // Existing rows need a value, and `DEFAULT NULL` does not supply one.
    if (!column.isNullable && !hasNonNullDefault) return false;

    if (defaultValue != null && !_isConstantDefault(defaultValue)) return false;

    // SQLite requires the default of a REFERENCES column to be NULL, so the
    // added column cannot point at a parent row that may not exist.
    if (column.foreignKey != null && hasNonNullDefault) return false;

    return true;
  }

  bool _isNullLiteral(String expression) =>
      expression.trim().toUpperCase() == 'NULL';

  /// Whether [expression] is a constant, as `ADD COLUMN` requires.
  bool _isConstantDefault(String expression) {
    final value = expression.trim();
    if (value.startsWith('(')) return false;
    return !const {
      'CURRENT_TIME',
      'CURRENT_DATE',
      'CURRENT_TIMESTAMP',
    }.contains(value.toUpperCase());
  }

  String _simpleAlter(AlterTable operation, TableDiff diff) {
    final table = escapeName(operation.tableName);
    return [
      ...operation.renamedColumns.entries.map(
        (entry) => '''
ALTER TABLE $table RENAME COLUMN ${escapeName(entry.key)} TO ${escapeName(entry.value)};''',
      ),
      for (final column in diff.droppedColumns)
        'ALTER TABLE $table DROP COLUMN ${escapeName(column.name)};',
      for (final column in diff.addedColumns)
        'ALTER TABLE $table ADD COLUMN ${_columnDefinition(column)};',
      for (final index in diff.droppedIndexes) dropIndex(index.name),
      for (final index in diff.addedIndexes) createIndex(index),
    ].join('\n');
  }

  /// Rebuilds [operation]'s table via SQLite's documented 12-step ALTER TABLE
  /// procedure (https://sqlite.org/lang_altertable.html#otheralter): shadow,
  /// copy, drop, rename, re-index.
  ///
  /// Only the target is rebuilt. Dependents are left alone and stay valid,
  /// because the table returns under its original name -- their `REFERENCES`
  /// clauses never stop being true. The shadow's own foreign keys therefore
  /// name the REAL tables, not other shadows.
  ///
  /// This procedure requires `foreign_keys = OFF` for its duration, which is
  /// the migrator's job: with them ON, `DROP TABLE` performs an implicit
  /// DELETE that fires `ON DELETE CASCADE` on referencing rows and destroys
  /// them. `PRAGMA defer_foreign_keys` does NOT prevent that -- it defers
  /// constraint *enforcement*, while cascade *actions* still run.
  String _rebuild(AlterTable operation, TableDiff diff) {
    // The un-backfillable case is refused in `alterTable`, before the split
    // between this and `_simpleAlter`: it is the same answer either way.
    return [
      // Not a statement -- `splitStatements` drops comment-only fragments.
      // It is here because the requirement is invisible in the SQL itself.
      '-- Requires foreign_keys = OFF (SQLite 12-step ALTER TABLE procedure).',
      '-- The migrator disables them around the transaction; `PRAGMA',
      '-- foreign_keys` inside one is silently a no-op.',
      _createShadow(operation.newTable),
      _copyTarget(operation, diff),
      'DROP TABLE ${escapeName(operation.tableName)};',
      '''
ALTER TABLE ${escapeName('__new_${operation.tableName}')} RENAME TO ${escapeName(operation.tableName)};''',
      for (final index in operation.newIndexes) createIndex(index),
    ].join('\n');
  }

  /// `CREATE TABLE "__new_<t>"`, its foreign keys naming the real tables.
  ///
  /// Nothing is re-targeted at a `__new_` name: only [table] is being rebuilt,
  /// and it is renamed back before anything reads it.
  String _createShadow(TableInfo table) {
    final defs = [
      ...table.columns.map(_columnDefinition),
      for (final entry in table.checks.entries)
        'CONSTRAINT ${escapeName(entry.key)} CHECK (${entry.value})',
    ].join(',\n  ');
    return 'CREATE TABLE ${escapeName('__new_${table.name}')} (\n  $defs\n);';
  }

  /// Copies the target's rows into its shadow: renamed columns read from
  /// their old name, added columns are omitted (their default applies),
  /// dropped columns are omitted on purpose.
  String _copyTarget(AlterTable operation, TableDiff diff) {
    final oldNameOf = {
      for (final entry in operation.renamedColumns.entries)
        entry.value: entry.key,
    };
    final copied = [
      for (final column in operation.newTable.columns)
        if (operation.oldTable.column(oldNameOf[column.name] ?? column.name) !=
            null)
          column.name,
    ];
    final targets = copied.map(escapeName).join(', ');
    final sources =
        copied.map((name) => escapeName(oldNameOf[name] ?? name)).join(', ');
    return '''
INSERT INTO ${escapeName('__new_${operation.tableName}')} ($targets) SELECT $sources FROM ${escapeName(operation.tableName)};''';
  }

  String _columnDefinition(ColumnInfo column) {
    final parts = <String>[
      escapeName(column.name),
      getColumnType(column),
    ];

    if (column.primaryKey) {
      parts.add('PRIMARY KEY');
      if (column.autoIncrement) {
        parts.add('AUTOINCREMENT');
      }
    }

    if (!column.isNullable && !column.primaryKey) {
      parts.add('NOT NULL');
    }

    if (column.defaultValue != null) {
      parts.add('DEFAULT ${column.defaultValue}');
    }

    if (column.foreignKey case final fk?) {
      final referencedTable = escapeName(fk.referencedTable);
      final referencedColumn = escapeName(fk.referencedColumn);
      parts.add('REFERENCES $referencedTable($referencedColumn)');
      if (fk.onDelete != null) parts.add('ON DELETE ${fk.onDelete}');
      if (fk.onUpdate != null) parts.add('ON UPDATE ${fk.onUpdate}');
    }

    return parts.join(' ');
  }
}
