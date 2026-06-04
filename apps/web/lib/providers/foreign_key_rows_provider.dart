import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

import '../utils/foreign_key_search_where.dart';
import 'table_rows_provider.dart';
import 'table_schema_provider.dart';

/// Query for loading FK picker rows (optional [search] filter).
final class ForeignKeyPickerQuery {
  const ForeignKeyPickerQuery({required this.foreignKey, this.search = ''});

  final ForeignKeyShape foreignKey;
  final String search;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForeignKeyPickerQuery && foreignKey == other.foreignKey && search == other.search;

  @override
  int get hashCode => Object.hash(foreignKey, search);
}

/// Loads rows from the table referenced by [query.foreignKey] for the FK picker dialog.
final foreignKeyRowsProvider = FutureProvider.family<TableRowsData?, ForeignKeyPickerQuery>((ref, query) async {
  if (!ref.binding.isClient) return null;

  final schema = ref.watch(tableSchemasProvider)[query.foreignKey.table];
  return _loadForeignKeyTableRows(
    sqliteName: query.foreignKey.table,
    schema: schema,
    foreignKey: query.foreignKey,
    search: query.search,
  );
});

Future<TableRowsData?> _loadForeignKeyTableRows({
  required String sqliteName,
  required TableSchemaShape? schema,
  required ForeignKeyShape foreignKey,
  required String search,
}) async {
  final fallbackColumns = schema == null ? <String>[] : schema.columns.map((c) => c.name).toList();
  final where = buildForeignKeySearchWhere(
    query: search,
    schema: schema,
    referencedColumnName: foreignKey.column,
    columnNamesFallback: fallbackColumns,
  );

  final data = await revaliServer.db.list(
    body: ListBody(table: sqliteName, limit: tableRowsPageSize, offset: 0, where: where),
  );

  final items = parseFkListItemsFromResponse(data);
  final total = switch (data['total']) {
    final int t => t,
    final num t => t.toInt(),
    _ => items.length,
  };

  if (items.isEmpty) {
    return TableRowsData(
      sqliteName: sqliteName,
      columns: const [],
      columnShapes: const [],
      rows: const [],
      total: total,
      truncated: false,
      schema: schema,
    );
  }

  final columnOrder = fkColumnOrderFromSchemaOrItems(schema, items);
  final columnShapes = [
    for (final name in columnOrder)
      schema?.columnNamed(name) ??
          ColumnShape(
            name: name,
            kind: ColumnShapeKind.text,
            isNullable: true,
            isPrimaryKey: false,
            autoIncrement: false,
            sqlType: 'TEXT',
          ),
  ];

  final rows = <List<Object?>>[
    for (final row in items) [for (final col in columnOrder) row[col]],
  ];

  return TableRowsData(
    sqliteName: sqliteName,
    columns: columnOrder,
    columnShapes: columnShapes,
    rows: rows,
    total: total,
    truncated: total > items.length,
    schema: schema,
  );
}

List<Map<String, Object?>> parseFkListItemsFromResponse(Map<String, Object?> data) {
  final itemsRaw = data['items'];
  if (itemsRaw is! List) return const [];

  return [
    for (final e in itemsRaw)
      {
        if (e is Map)
          for (final MapEntry(:key, :value) in e.entries) key.toString(): value as Object?,
      },
  ];
}

List<String> fkColumnOrderFromSchemaOrItems(TableSchemaShape? schema, List<Map<String, Object?>> items) {
  if (schema != null && schema.columns.isNotEmpty) {
    final pk = schema.columns.where((c) => c.isPrimaryKey).map((c) => c.name).toList();
    final labels = schema.columns
        .where((c) => !c.isPrimaryKey && !c.isSecret && c.kind == ColumnShapeKind.text)
        .map((c) => c.name)
        .where((n) => n == 'name' || n == 'title' || n == 'email' || n == 'label')
        .toList();
    final rest = [
      for (final c in schema.columns)
        if (!pk.contains(c.name) && !labels.contains(c.name) && !c.isSecret) c.name,
    ];
    return [...pk, ...labels, ...rest];
  }

  return items.first.keys.toList();
}

/// Column index for the referenced column in loaded FK table data.
int? foreignKeyPrimaryColumnIndex(TableRowsData data, ForeignKeyShape foreignKey) {
  for (var i = 0; i < data.columns.length; i++) {
    if (data.columns[i] == foreignKey.column) return i;
  }
  return data.columns.isNotEmpty ? 0 : null;
}

/// Referenced column value from a loaded row.
String? foreignKeyValueFromRow(TableRowsData data, ForeignKeyShape foreignKey, List<Object?> row) {
  final index = foreignKeyPrimaryColumnIndex(data, foreignKey);
  if (index == null) return null;
  final value = row[index];
  if (value == null) return null;
  return '$value';
}

/// Human-readable label for a FK table row (first text-like column after PK).
String foreignKeyRowLabel(TableRowsData data, List<Object?> row) {
  for (var i = 0; i < data.columnShapes.length; i++) {
    final shape = data.columnShapes[i];
    if (shape.isPrimaryKey) continue;
    if (shape.isSecret) continue;
    if (shape.kind == ColumnShapeKind.text ||
        shape.kind == ColumnShapeKind.email ||
        shape.kind == ColumnShapeKind.enum_) {
      final v = row[i];
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
  }
  return '';
}

/// User-facing message when a typed FK value does not exist.
const foreignKeyReferenceInvalidMessage = 'That reference does not match an existing row.';
