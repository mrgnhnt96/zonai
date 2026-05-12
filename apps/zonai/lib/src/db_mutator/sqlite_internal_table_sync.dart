import 'package:raindrop/ddl.dart';
import 'package:raindrop/raindrop.dart'
    show Column, Raindrop, ReferentialAction, Schema, Table;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

/// Keeps SQLite internal tables aligned with Raindrop/Zonai schema definitions:
/// creates missing tables and rebuilds existing ones when column metadata diverges.
final class SqliteInternalTableSync {
  SqliteInternalTableSync({
    this.dialect = const SQLiteDialect(),
    this.onRebuildScheduled,
  });

  final SQLiteDialect dialect;

  /// Invoked immediately before rewriting a mismatched internal table inside a txn.
  final void Function(String message)? onRebuildScheduled;

  Future<void> ensureMatchingTable<S extends Schema<S>>(
    Raindrop db,
    S schema,
  ) async {
    final meta = Table.getFor(schema);
    final expected = [
      for (final c in meta.columns) _columnInfoFromRaindropColumn(c),
    ].toList();

    final exists = await _sqliteTableExists(db, meta.name);

    if (!exists) {
      await db.execute(
        _sqliteCreateTableDdl(dialect, meta.name, expected, ifNotExists: true),
      );
      return;
    }

    final actual = await _readPragmaTableInfo(db, meta.name);
    if (_internalSchemasMatch(expected, actual)) {
      return;
    }

    onRebuildScheduled?.call(
      'Rebuilding internal table "${meta.name}" '
      '(stored columns diverge from Dart schema)',
    );

    await _sqliteRebuildTablePreservingOverlap(
      db,
      dialect,
      meta.name,
      expected,
      existingNames: actual.map((c) => c.name).toSet(),
    );
  }

  Future<bool> _sqliteTableExists(Raindrop db, String tableName) async {
    final r = await db.execute(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [tableName],
    );
    return r.rows.isNotEmpty;
  }

  Future<List<_SqlitePragmaColumn>> _readPragmaTableInfo(
    Raindrop db,
    String tableName,
  ) async {
    final r = await db.execute(
      'SELECT cid, name, type, "notnull", dflt_value, pk FROM pragma_table_info(?)',
      [tableName],
    );
    return [
      for (final row in r.rows)
        _SqlitePragmaColumn(
          cid: _sqliteInt(row[0]),
          name: row[1]! as String,
          type: (row[2] as String?) ?? '',
          notNull: _sqliteInt(row[3]) != 0,
          defaultValue: row[4]?.toString(),
          primaryKeyOrdinal: _sqliteInt(row[5]),
        ),
    ];
  }

  Future<void> _sqliteRebuildTablePreservingOverlap(
    Raindrop db,
    SQLiteDialect dialect,
    String tableName,
    List<ColumnInfo> expected, {
    required Set<String> existingNames,
  }) async {
    final escaped = dialect.escapeName(tableName);
    final tempBaseName = '${tableName}_zonai_ib_rebuild';
    final tempEscaped = dialect.escapeName(tempBaseName);

    await db.transaction((tx) async {
      await tx.execute('DROP TABLE IF EXISTS $tempEscaped');

      await tx.execute(
        _sqliteCreateTableDdl(
          dialect,
          tempBaseName,
          expected,
          ifNotExists: false,
        ),
      );

      final transfer = <String>[
        for (final column in expected)
          if (existingNames.contains(column.name)) column.name,
      ];

      if (transfer.isNotEmpty) {
        final escapedCols = transfer.map(dialect.escapeName).join(', ');
        await tx.execute(
          'INSERT INTO $tempEscaped ($escapedCols) '
          'SELECT $escapedCols FROM $escaped',
        );
      }

      await tx.execute('DROP TABLE $escaped');
      await tx.execute('ALTER TABLE $tempEscaped RENAME TO $escaped');
    });
  }

  ColumnInfo _columnInfoFromRaindropColumn(Column<dynamic, dynamic> c) {
    final sqlType =
        c.sqlType ??
        (throw StateError('Column "${c.name}" has no sqlType'));
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

int _sqliteInt(Object? raw) => switch (raw) {
  null => 0,
  final int i => i,
  final num n => n.toInt(),
  _ => throw StateError('Unsupported integer-ish value: ${raw.runtimeType}'),
};

final class _SqlitePragmaColumn {
  _SqlitePragmaColumn({
    required this.cid,
    required this.name,
    required this.type,
    required this.notNull,
    required this.defaultValue,
    required this.primaryKeyOrdinal,
  });

  final int cid;
  final String name;
  final String type;
  final bool notNull;

  /// Pragma `dflt_value` (comparison with [ColumnInfo.defaultValue] is skipped).
  final String? defaultValue;

  /// Non‑zero iff this column is part of `PRIMARY KEY` (composite keys repeat for each column).
  final int primaryKeyOrdinal;
}

bool _sqliteDeclaredTypeCompatible(String expected, String actual) {
  final a = actual.trim();
  if (a.isEmpty) {
    return true;
  }
  return _sqliteAffinityClass(expected) == _sqliteAffinityClass(a);
}

/// Normalized SQLite type affinity grouping (declaration strings only).
String _sqliteAffinityClass(String declaredType) {
  var s = declaredType.trim().toUpperCase();
  while (s.startsWith('(') && s.endsWith(')') && s.length > 1) {
    s = s.substring(1, s.length - 1).trim().toUpperCase();
  }
  if (s.isEmpty) return 'TEXT';
  if (s.contains('INT')) return 'INTEGER';
  final isTextLike =
      s.contains('CHAR') ||
      s == 'CLOB' ||
      s == 'TEXT' ||
      s.contains('TEXT') ||
      s.contains('STRING');
  if (isTextLike) return 'TEXT';
  final isReal = s == 'REAL' || s.contains('FLOA') || s.contains('DOUB');
  if (isReal) return 'REAL';
  final isBlob = s == 'BLOB' || s.contains('BINARY');
  if (isBlob) return 'BLOB';
  return 'NUMERIC';
}

bool _internalSchemasMatch(
  List<ColumnInfo> expected,
  List<_SqlitePragmaColumn> actual,
) {
  final byName = {for (final c in actual) c.name: c};
  if (byName.length != expected.length) {
    return false;
  }
  for (final column in expected) {
    final a = byName[column.name];
    if (a == null) {
      return false;
    }
    if (!_sqliteDeclaredTypeCompatible(column.type, a.type)) {
      return false;
    }
    if (column.primaryKey != (a.primaryKeyOrdinal != 0)) {
      return false;
    }
    final expectAllowsNull = column.isNullable && !column.primaryKey;
    final actualAllowsNull = !a.notNull && a.primaryKeyOrdinal == 0;
    if (expectAllowsNull != actualAllowsNull) {
      return false;
    }
  }
  return true;
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
