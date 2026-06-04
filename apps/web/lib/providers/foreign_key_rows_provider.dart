import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

import 'table_rows_provider.dart';
import 'table_schema_provider.dart';

/// Loads rows from the table referenced by [foreignKey] for the FK picker dialog.
final foreignKeyRowsProvider = FutureProvider.family<TableRowsData?, ForeignKeyShape>((ref, foreignKey) async {
  if (!ref.binding.isClient) return null;

  final schema = ref.watch(tableSchemasProvider)[foreignKey.table];
  return _loadForeignKeyTableRows(sqliteName: foreignKey.table, schema: schema);
});

Future<TableRowsData?> _loadForeignKeyTableRows({
  required String sqliteName,
  required TableSchemaShape? schema,
}) async {
  final data = await revaliServer.db.list(
    body: ListBody(table: sqliteName, limit: tableRowsPageSize, offset: 0),
  );

  final items = _parseFkListItems(data);
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

  final columnOrder = _fkColumnOrder(schema, items);
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

List<Map<String, Object?>> _parseFkListItems(Map<String, Object?> data) {
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

List<String> _fkColumnOrder(TableSchemaShape? schema, List<Map<String, Object?>> items) {
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

/// Column index for the referenced PK in loaded FK table data.
int? foreignKeyPrimaryColumnIndex(TableRowsData data, ForeignKeyShape foreignKey) {
  for (var i = 0; i < data.columns.length; i++) {
    if (data.columns[i] == foreignKey.column) return i;
  }
  return data.columns.isNotEmpty ? 0 : null;
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
