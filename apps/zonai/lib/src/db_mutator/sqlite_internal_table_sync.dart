import 'package:raindrop/ddl.dart';
import 'package:raindrop/raindrop.dart'
    show Column, Raindrop, ReferentialAction, Schema, Table;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

/// Ensures framework-managed SQLite tables exist.
///
/// Schema evolution is handled by [InternalDbMigrate] (versioned migrations).
/// This helper only creates tables that are entirely missing.
final class SqliteInternalTableSync {
  SqliteInternalTableSync({this.dialect = const SQLiteDialect()});

  final SQLiteDialect dialect;

  Future<void> ensureMatchingTable<S extends Schema<R>, R>(
    Raindrop db,
    S schema,
  ) async {
    final meta = Table.getFor(schema);
    final expected = [
      for (final c in meta.columns) _columnInfoFromRaindropColumn(c),
    ].toList();

    final exists = await _sqliteTableExists(db, meta.name);
    if (exists) {
      return;
    }

    await db.execute(
      _sqliteCreateTableDdl(dialect, meta.name, expected, ifNotExists: true),
    );
  }

  Future<bool> _sqliteTableExists(Raindrop db, String tableName) async {
    final r = await db.execute(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [tableName],
    );
    return r.rows.isNotEmpty;
  }

  ColumnInfo _columnInfoFromRaindropColumn(Column<dynamic, dynamic> c) {
    final sqlType =
        c.sqlType ?? (throw StateError('Column "${c.name}" has no sqlType'));
    final fkRef = c.foreignKeyReference;
    return ColumnInfo(
      name: c.name,
      type: sqlType,
      isNullable: c.isNullable,
      primaryKey: c.isPrimaryKey,
      autoIncrement: c.autoIncrement,
      defaultValue: c.defaultValue,
      foreignKey: fkRef == null
          ? null
          : ForeignKeyInfo(
              referencedTable: fkRef.referencedTable,
              referencedColumn: fkRef.referencedColumnName,
              onDelete: _referentialSql(fkRef.onDelete),
              onUpdate: _referentialSql(fkRef.onUpdate),
            ),
    );
  }
}

String _sqliteCreateTableDdl(
  SQLiteDialect dialect,
  String tableName,
  List<ColumnInfo> columns, {
  required bool ifNotExists,
}) {
  final defs = columns
      .map((c) => _sqliteColumnDefinition(dialect, c))
      .join(',\n  ');
  final op = ifNotExists ? 'CREATE TABLE IF NOT EXISTS' : 'CREATE TABLE';
  return '$op ${dialect.escapeName(tableName)} (\n'
      '  $defs\n'
      ');';
}

String _sqliteColumnDefinition(SQLiteDialect dialect, ColumnInfo column) {
  final parts = <String>[dialect.escapeName(column.name), column.type];
  if (column.primaryKey) {
    parts.add('PRIMARY KEY');
    if (column.autoIncrement) {
      parts.add('AUTOINCREMENT');
    }
  }
  if (!column.isNullable && !column.primaryKey) {
    parts.add('NOT NULL');
  }
  if (column.defaultValue case final dv?) {
    parts.add('DEFAULT $dv');
  }
  if (column.foreignKey case final fk?) {
    parts.add(
      'REFERENCES ${dialect.escapeName(fk.referencedTable)}(${dialect.escapeName(fk.referencedColumn)})',
    );
    if (fk.onDelete case final od?) parts.add('ON DELETE $od');
    if (fk.onUpdate case final ou?) parts.add('ON UPDATE $ou');
  }
  return parts.join(' ');
}

String? _referentialSql(ReferentialAction? a) {
  return switch (a) {
    null => null,
    ReferentialAction.cascade => 'CASCADE',
    ReferentialAction.setNull => 'SET NULL',
    ReferentialAction.setDefault => 'SET DEFAULT',
    ReferentialAction.restrict => 'RESTRICT',
    ReferentialAction.noAction => 'NO ACTION',
  };
}
