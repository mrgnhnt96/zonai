import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

import 'table_focus_provider.dart';
import 'table_schema_provider.dart';

final class TableRowsData {
  const TableRowsData({
    required this.columns,
    required this.columnShapes,
    required this.rows,
    required this.truncated,
    required this.sqliteName,
    this.schema,
  });

  final List<String> columns;
  final List<ColumnShape> columnShapes;
  final List<List<Object?>> rows;
  final bool truncated;
  final String sqliteName;
  final TableSchemaShape? schema;
}

final tableRowsProvider = AsyncNotifierProvider<TableRowsNotifier, TableRowsData?>(
  TableRowsNotifier.new,
);

class TableRowsNotifier extends AsyncNotifier<TableRowsData?> {
  @override
  Future<TableRowsData?> build() async {
    final focus = ref.watch(tableFocusProvider);
    if (focus == null) return null;
    if (!ref.binding.isClient) return null;

    final schema = ref.watch(tableSchemaProvider);

    Map<String, Object?> data;

    try {
      data = await revaliServer.db.list(body: ListBody(table: focus.sqliteName));
    } catch (e) {
      throw StateError('Failed to get table rows: $e');
    }

    final itemsRaw = data['items'];
    if (itemsRaw is! List) {
      throw StateError('Invalid /db/list payload: missing items list');
    }

    final items = <Map<String, Object?>>[
      for (final e in itemsRaw)
        {
          if (e is Map)
            for (final MapEntry(:key, :value) in e.entries) key.toString(): value as Object?,
        },
    ];

    if (items.isEmpty) {
      return TableRowsData(
        sqliteName: focus.sqliteName,
        columns: const [],
        columnShapes: const [],
        rows: const [],
        truncated: false,
        schema: schema,
      );
    }

    final columnOrder = _columnOrder(schema, items);
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

    final total = switch (data['total']) {
      final int t => t,
      final num t => t.toInt(),
      _ => items.length,
    };

    return TableRowsData(
      sqliteName: focus.sqliteName,
      columns: columnOrder,
      columnShapes: columnShapes,
      rows: rows,
      truncated: total > items.length,
      schema: schema,
    );
  }
}

List<String> _columnOrder(TableSchemaShape? schema, List<Map<String, Object?>> items) {
  if (schema != null && schema.columns.isNotEmpty) {
    final names = schema.columns.map((c) => c.name).toList();
    final extra = <String>{};
    for (final row in items) {
      extra.addAll(row.keys.where((key) => !names.contains(key)));
    }
    return [...names, ...extra.toList()..sort()];
  }

  final columns = <String>{};
  for (final row in items) {
    columns.addAll(row.keys);
  }
  return columns.toList()..sort();
}
