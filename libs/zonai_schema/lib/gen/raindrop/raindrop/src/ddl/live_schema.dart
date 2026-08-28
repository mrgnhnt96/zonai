// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:meta/meta.dart';

/// A schema as a database itself reports it, rather than as the SQL that was
/// executed says it should be.
///
/// Read back out of a real database — SQLite's `pragma_table_info` and
/// friends, postgres's `information_schema` — so that what it describes is
/// the outcome, not the intent. That distinction is the whole point: a
/// snapshot records what the schema asked for, and until something reads the
/// database there is nothing recording what it got.
///
/// Crosses the isolate boundary between the CLI and a driver as a plain map,
/// so both sides agree on the shape without the CLI depending on any driver.
@immutable
class LiveSchema {
  /// Creates a live schema.
  const LiveSchema({required this.tables, required this.indexes});

  /// Reads a live schema back from its map form.
  factory LiveSchema.fromMap(Map<String, Object?> map) {
    return LiveSchema(
      tables: {
        for (final entry
            in (map['tables']! as Map).cast<String, Object?>().entries)
          entry.key:
              LiveTable.fromMap((entry.value! as Map).cast<String, Object?>()),
      },
      indexes: {
        for (final entry
            in (map['indexes']! as Map).cast<String, Object?>().entries)
          entry.key:
              LiveIndex.fromMap((entry.value! as Map).cast<String, Object?>()),
      },
    );
  }

  /// The user tables, by name.
  final Map<String, LiveTable> tables;

  /// The explicitly created indexes, by name.
  ///
  /// The implicit indexes a database builds for PRIMARY KEY and UNIQUE
  /// constraints are not here: they are not in a schema snapshot either, and
  /// comparing them would report a difference on every table.
  final Map<String, LiveIndex> indexes;

  /// This schema's map form.
  Map<String, Object?> toMap() => {
        'tables': {
          for (final entry in tables.entries) entry.key: entry.value.toMap(),
        },
        'indexes': {
          for (final entry in indexes.entries) entry.key: entry.value.toMap(),
        },
      };
}

/// A table as a database reports it.
@immutable
class LiveTable {
  /// Creates a live table.
  const LiveTable({
    required this.name,
    required this.columns,
    required this.foreignKeys,
    this.definition,
  });

  /// Reads a live table back from its map form.
  factory LiveTable.fromMap(Map<String, Object?> map) {
    return LiveTable(
      name: map['name']! as String,
      definition: map['definition'] as String?,
      columns: {
        for (final entry
            in (map['columns']! as Map).cast<String, Object?>().entries)
          entry.key:
              LiveColumn.fromMap((entry.value! as Map).cast<String, Object?>()),
      },
      foreignKeys: [
        for (final fk in map['foreignKeys']! as List<Object?>)
          LiveForeignKey.fromMap((fk! as Map).cast<String, Object?>()),
      ],
    );
  }

  /// The table name.
  final String name;

  /// The columns, by name.
  ///
  /// By name and never by position: `ALTER TABLE ... ADD COLUMN` appends,
  /// while a schema keeps the column wherever it is declared, so the two
  /// orders legitimately diverge and comparing them would be noise.
  final Map<String, LiveColumn> columns;

  /// The table's foreign keys.
  final List<LiveForeignKey> foreignKeys;

  /// The `CREATE TABLE` statement the database stored, where it keeps one.
  ///
  /// SQLite does; postgres does not. Only used for the parts no portable
  /// introspection exposes — CHECK constraints — and a driver that has none
  /// leaves it null, which the comparison reports as "not checked" rather
  /// than as agreement.
  final String? definition;

  /// This table's map form.
  Map<String, Object?> toMap() => {
        'name': name,
        if (definition != null) 'definition': definition,
        'columns': {
          for (final entry in columns.entries) entry.key: entry.value.toMap(),
        },
        'foreignKeys': [for (final fk in foreignKeys) fk.toMap()],
      };
}

/// A column as a database reports it.
@immutable
class LiveColumn {
  /// Creates a live column.
  const LiveColumn({
    required this.name,
    required this.type,
    required this.notNull,
    required this.primaryKey,
    this.defaultValue,
  });

  /// Reads a live column back from its map form.
  factory LiveColumn.fromMap(Map<String, Object?> map) => LiveColumn(
        name: map['name']! as String,
        type: map['type']! as String,
        notNull: map['notNull']! as bool,
        primaryKey: map['primaryKey']! as bool,
        defaultValue: map['defaultValue'] as String?,
      );

  /// The column name.
  final String name;

  /// The declared type.
  final String type;

  /// Whether the column carries `NOT NULL`.
  final bool notNull;

  /// Whether the column is part of the primary key.
  final bool primaryKey;

  /// The declared default, as the database stored the expression.
  final String? defaultValue;

  /// This column's map form.
  Map<String, Object?> toMap() => {
        'name': name,
        'type': type,
        'notNull': notNull,
        'primaryKey': primaryKey,
        if (defaultValue != null) 'defaultValue': defaultValue,
      };
}

/// A foreign key as a database reports it.
@immutable
class LiveForeignKey {
  /// Creates a live foreign key.
  const LiveForeignKey({
    required this.from,
    required this.referencedTable,
    required this.referencedColumn,
    required this.onDelete,
    required this.onUpdate,
  });

  /// Reads a live foreign key back from its map form.
  factory LiveForeignKey.fromMap(Map<String, Object?> map) => LiveForeignKey(
        from: map['from']! as String,
        referencedTable: map['referencedTable']! as String,
        referencedColumn: map['referencedColumn']! as String,
        onDelete: map['onDelete']! as String,
        onUpdate: map['onUpdate']! as String,
      );

  /// The referencing column.
  final String from;

  /// The referenced table.
  final String referencedTable;

  /// The referenced column.
  final String referencedColumn;

  /// The `ON DELETE` action, `NO ACTION` when none was declared.
  final String onDelete;

  /// The `ON UPDATE` action, `NO ACTION` when none was declared.
  final String onUpdate;

  /// This foreign key's map form.
  Map<String, Object?> toMap() => {
        'from': from,
        'referencedTable': referencedTable,
        'referencedColumn': referencedColumn,
        'onDelete': onDelete,
        'onUpdate': onUpdate,
      };

  @override
  String toString() => '$from -> $referencedTable($referencedColumn) '
      'ON DELETE $onDelete ON UPDATE $onUpdate';
}

/// An index as a database reports it.
@immutable
class LiveIndex {
  /// Creates a live index.
  const LiveIndex({
    required this.name,
    required this.tableName,
    required this.columns,
    required this.isUnique,
    this.where,
  });

  /// Reads a live index back from its map form.
  factory LiveIndex.fromMap(Map<String, Object?> map) => LiveIndex(
        name: map['name']! as String,
        tableName: map['tableName']! as String,
        columns: [
          for (final column in map['columns']! as List<Object?>)
            column! as String,
        ],
        isUnique: map['isUnique']! as bool,
        where: map['where'] as String?,
      );

  /// The index name.
  final String name;

  /// The table it indexes.
  final String tableName;

  /// The indexed columns, in index order.
  final List<String> columns;

  /// Whether the index is unique.
  final bool isUnique;

  /// The partial-index predicate, or null when the index covers every row.
  final String? where;

  /// This index's map form.
  Map<String, Object?> toMap() => {
        'name': name,
        'tableName': tableName,
        'columns': columns,
        'isUnique': isUnique,
        if (where != null) 'where': where,
      };
}
