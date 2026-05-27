import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

import 'table_focus_provider.dart';

final class TableRowsData {
  const TableRowsData({
    required this.columns,
    required this.rows,
    required this.truncated,
    required this.sqliteName,
  });

  final List<String> columns;
  final List<List<Object?>> rows;
  final bool truncated;
  final String sqliteName;
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
      return TableRowsData(sqliteName: focus.sqliteName, columns: const [], rows: const [], truncated: false);
    }

    final columns = <String>{};
    for (final row in items) {
      columns.addAll(row.keys);
    }
    final columnOrder = columns.toList()..sort();

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
      rows: rows,
      truncated: total > items.length,
    );
  }
}
