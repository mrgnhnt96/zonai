// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/ddl.dart';
import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_delegate.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// The tables a schema snapshot never describes, and which must therefore
/// never be compared against one.
const _reserved = {'_raindrop_migrations'};

/// {@macro schema_inspector}
///
/// SQLite can do this for nothing: the scratch database is `:memory:`, so
/// replaying a project's whole history costs a few milliseconds and touches
/// no file. Picto's 26 migrations replay in about a second.
class SQLiteSchemaInspector extends SchemaInspector {
  /// {@macro schema_inspector}
  const SQLiteSchemaInspector();

  @override
  Future<List<LiveSchema>> replay(List<Migration> migrations) async {
    // Foreign keys ON, exactly as a real database has them, so that the
    // migrator's own `PRAGMA foreign_keys = OFF` around each migration has
    // something to turn off and restore. A rebuild replayed with them left
    // on cascades children away at `DROP TABLE` and the schema that comes
    // out is not the schema a real deployment would have.
    final database = sqlite3.openInMemory()
      ..execute('PRAGMA foreign_keys = ON;');
    try {
      // The real migrator, not a bare loop of `execute`: it owns the
      // foreign-key handling a table rebuild depends on, and its
      // `PRAGMA foreign_key_check` before commit is what turns a migration
      // that silently broke a reference into a thrown error here.
      //
      // Handed a growing prefix so the schema can be read between them.
      // `migrate` skips what it has already applied and re-checks its
      // checksums, so this is the same work a real deployment does, not a
      // repetition of it.
      final db = Raindrop(SQLiteDelegate(database));
      final schemas = <LiveSchema>[];
      for (var i = 0; i < migrations.length; i++) {
        await migrate(db, migrations.sublist(0, i + 1));
        schemas.add(read(database));
      }
      return schemas;
    } finally {
      database.dispose();
    }
  }

  /// Reads [database]'s schema back out of it.
  ///
  /// Through the pragmas rather than by re-reading the SQL that was executed:
  /// what is wanted is the schema the database ended up with, which is the
  /// one thing the executed text cannot be trusted to say.
  static LiveSchema read(CommonDatabase database) {
    final tables = <String, LiveTable>{};
    final indexes = <String, LiveIndex>{};

    final rows = database.select(
      '''
SELECT name, sql FROM sqlite_master
WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
ORDER BY name''',
    );

    for (final row in rows) {
      final name = row['name'] as String;
      if (_reserved.contains(name)) continue;

      tables[name] = LiveTable(
        name: name,
        definition: row['sql'] as String?,
        columns: {
          for (final column
              in database.select('SELECT * FROM pragma_table_info(?)', [name]))
            column['name'] as String: LiveColumn(
              name: column['name'] as String,
              type: column['type'] as String,
              notNull: (column['notnull'] as int) != 0,
              primaryKey: (column['pk'] as int) != 0,
              defaultValue: column['dflt_value'] as String?,
            ),
        },
        foreignKeys: [
          for (final fk in database
              .select('SELECT * FROM pragma_foreign_key_list(?)', [name]))
            LiveForeignKey(
              from: fk['from'] as String,
              referencedTable: fk['table'] as String,
              referencedColumn: fk['to'] as String,
              onDelete: fk['on_delete'] as String,
              onUpdate: fk['on_update'] as String,
            ),
        ],
      );
    }

    for (final table in tables.keys) {
      // `origin = 'c'` is "created by CREATE INDEX". The implicit indexes
      // SQLite builds for PRIMARY KEY and UNIQUE constraints ('pk' and 'u')
      // are not in a snapshot, so comparing them would report a difference
      // on every table that has a key.
      for (final index in database.select(
        "SELECT * FROM pragma_index_list(?) WHERE origin = 'c'",
        [table],
      )) {
        final name = index['name'] as String;
        indexes[name] = LiveIndex(
          name: name,
          tableName: table,
          columns: [
            for (final column in database.select(
              'SELECT name FROM pragma_index_info(?) ORDER BY seqno',
              [name],
            ))
              column['name'] as String,
          ],
          isUnique: (index['unique'] as int) != 0,
          where: (index['partial'] as int) == 0
              ? null
              : _predicateOf(database, name),
        );
      }
    }

    return LiveSchema(tables: tables, indexes: indexes);
  }

  /// A partial index's `WHERE` predicate.
  ///
  /// No pragma exposes it -- `pragma_index_list` only says *whether* an index
  /// is partial -- so it comes off the stored `CREATE INDEX` text, which is
  /// the only place SQLite keeps it.
  static String? _predicateOf(CommonDatabase database, String name) {
    final rows = database.select(
      "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
      [name],
    );
    if (rows.isEmpty) return null;
    final sql = rows.first['sql'] as String?;
    if (sql == null) return null;

    // The predicate runs to the end of the statement, so the last WHERE at
    // paren depth zero opens it. Scanning rather than a regex because a
    // predicate may itself contain parentheses and quoted text.
    var depth = 0;
    for (var i = 0; i < sql.length; i++) {
      switch (sql[i]) {
        case '(':
          depth++;
        case ')':
          depth--;
        case ' ' when depth == 0:
          if (sql.length >= i + 7 &&
              sql.substring(i + 1, i + 6).toUpperCase() == 'WHERE') {
            return sql.substring(i + 7).trim();
          }
      }
    }
    return null;
  }
}
