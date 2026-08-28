// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:zonai_schema/gen/raindrop/raindrop/ddl.dart';
import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';

/// Serves [generator] over the isolate command protocol the CLI speaks.
///
/// Sends a command port back over [sendPort], then answers `generate`
/// messages until the returned [ReceivePort] is closed.
///
/// A driver's DDL entrypoint is the only place this belongs:
///
/// ```dart
/// void main(List<String> args, SendPort sendPort) =>
///     serveDdlGenerator(MyDdlGenerator(), sendPort);
/// ```
ReceivePort serveDdlGenerator(
  DdlGenerator generator,
  SendPort sendPort, {
  SchemaInspector? inspector,
}) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is Map<String, dynamic>) {
      final replyPort = message['replyPort'] as SendPort;
      final action = message['action'] as String? ?? 'generate';

      try {
        switch (action) {
          case 'generate':
            final sql = generator.generate(
              (message['operations'] as List<dynamic>)
                  .map((o) => DiffOperation.fromMap((o as Map).cast()))
                  .toList(),
            );

            replyPort.send({'success': true, 'sql': sql});
          case 'replay':
            // A driver that cannot build a scratch database says so, and the
            // caller reports it. It must never read as agreement: "nothing
            // was compared" and "nothing differs" are the same green
            // otherwise, which is the whole failure this check exists to
            // stop happening one level up.
            if (inspector == null) {
              replyPort.send({
                'success': false,
                'unsupported': true,
                'error': 'The "${generator.dialect.name}" driver cannot '
                    'replay migrations: it serves no SchemaInspector, so '
                    'there is no scratch database to apply them to.',
              });
              return;
            }
            final schemas = await inspector.replay([
              for (final entry in message['migrations']! as List<dynamic>)
                Migration(
                  (entry as Map)['tag'] as String,
                  entry['sql'] as String,
                ),
            ]);
            replyPort.send({
              'success': true,
              'schemas': [for (final schema in schemas) schema.toMap()],
            });
          default:
            replyPort.send(
              {'success': false, 'error': 'Unknown action: $action'},
            );
        }
      } on Object catch (e, st) {
        replyPort.send({'success': false, 'error': '$e\n$st'});
      }
    }
  });

  return receivePort;
}

/// {@template schema_inspector}
/// Applies migrations to a throwaway database and reports the schema they
/// actually produce.
///
/// This is the half of migration correctness nothing else can answer. A
/// snapshot records what the schema asked for and the `.sql` records what
/// will run, and once a human edits the `.sql` — which is a supported thing
/// to do — the two part company silently and every later migration is
/// computed against the snapshot rather than against reality.
///
/// Implemented by drivers that can stand a database up on their own.
/// SQLite can, in memory, for nothing. A driver that needs a server does not
/// implement this, and the caller is told so rather than being told nothing
/// is wrong.
/// {@endtemplate}
abstract class SchemaInspector {
  /// {@macro schema_inspector}
  const SchemaInspector();

  /// Applies [migrations] in order to an empty scratch database, reading the
  /// schema back out of it after each one.
  ///
  /// After each, not only at the end, because a later migration can HEAL an
  /// earlier one's divergence and hide it. Picto's `recordings.sequence`
  /// gained a default its schema never declared in migration 3 and lost it
  /// again in migration 10, when an unrelated change rebuilt the table from
  /// the schema -- so a check that only looked at the newest snapshot would
  /// have reported that project clean while it was wrong for seven
  /// migrations, and while one of those migrations was a full table rebuild
  /// that existed only to correct it.
  ///
  /// The result is parallel to [migrations].
  Future<List<LiveSchema>> replay(List<Migration> migrations);
}

/// {@template ddl_generator}
/// Abstract interface for generating DDL statements from diff operations.
///
/// Each database dialect provides its own implementation, and its package's
/// `lib/ddl.dart` defines a main method serving it so the CLI can execute it
/// dynamically:
/// ```dart
/// void main(List<String> args, SendPort sendPort) =>
///     serveDdlGenerator(MyDdlGenerator(), sendPort);
///
/// class MyDdlGenerator extends DdlGenerator {
///   const MyDdlGenerator() : super(dialect: const MyDialect());
///
///   ...
/// }
/// ```
/// {@endtemplate}
abstract class DdlGenerator {
  /// {@macro ddl_generator}
  const DdlGenerator({required this.dialect});

  /// The SQL dialect used by this generator.
  final SqlDialect dialect;

  /// Generates SQL DDL statements from a list of diff operations.
  ///
  /// Overridable so a dialect can validate ACROSS operations (e.g. SQLite
  /// rejects a rebuild whose dependent table is itself altered in the same
  /// run), overrides should still delegate here for the per-operation work.
  String generate(List<DiffOperation> operations) {
    return [
      for (final op in operations) _nonBlank(op, render(op)),
    ].join('\n\n');
  }

  /// Renders a single operation through the dialect's methods.
  String render(DiffOperation operation) => switch (operation) {
        CreateTable(:final table) => createTable(table),
        DropTable(:final tableName) => dropTable(tableName),
        final AlterTable alter => alterTable(alter),
        CreateIndex(:final index) => createIndex(index),
        DropIndex(:final indexName) => dropIndex(indexName),
      };

  String _nonBlank(DiffOperation operation, String sql) {
    if (sql.trim().isEmpty) {
      throw StateError('${operation.describe()} produced no SQL.');
    }
    return sql;
  }

  /// Generates a CREATE TABLE statement.
  String createTable(TableInfo table);

  /// Generates a DROP TABLE statement.
  String dropTable(String tableName);

  /// Expresses every change [operation] carries, column changes, checks,
  /// and this table's index changes.
  String alterTable(AlterTable operation);

  /// Generates a CREATE INDEX statement.
  String createIndex(IndexInfo index);

  /// Generates a DROP INDEX statement.
  String dropIndex(String indexName);

  /// Gets the SQL type string for a column.
  String getColumnType(ColumnInfo column);

  /// Refuses [columns] being added to the existing table [tableName] when one
  /// of them is `NOT NULL` and has no default.
  ///
  /// The rows that are already there would have no value, so no statement can
  /// express the change: SQLite's `ADD COLUMN` rejects it outright, a rebuild
  /// has nothing to select into the new column, and postgres's `ADD COLUMN`
  /// fails with "contains null values".
  ///
  /// Refusing HERE, while the migration is being written, is the whole point.
  /// Every one of those failures happens at apply time and only on a table
  /// with rows in it -- so the migration passes on every empty database (CI,
  /// every dev machine, every test) and fails exactly once, in production.
  /// A generate-time refusal is the same information delivered to the person
  /// who can still do something about it.
  ///
  /// Called by each driver's [alterTable]; the wording lives here so that two
  /// drivers cannot answer the same question differently.
  @protected
  void requireBackfillableAdds(
    String tableName,
    Iterable<ColumnInfo> columns,
  ) {
    for (final column in columns) {
      if (column.isNullable || column.defaultValue != null) continue;
      throw UnsupportedError(
        '''
Adding NOT NULL column "${column.name}" to "$tableName" without a default: the rows already in the table have no value to backfill.

Give the column a defaultValue in the schema, which is what fills them:

    ${column.name} = \$.<type>('${column.name}', (row) => row.<field>, defaultValue: <value>)

A defaultValue is permanent -- it stays on the column and applies to every later insert. If you only mean to fill the rows that exist today, write this one migration by hand with `generate --empty`.''',
      );
    }
  }

  /// Escape [name] through the [dialect].
  ///
  /// Allows for overriding if necessary.
  String escapeName(String name) => dialect.escapeName(name);
}
