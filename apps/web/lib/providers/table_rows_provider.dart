import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

import '../utils/table_row_edit.dart';
import '../utils/table_row_key.dart';
import '../utils/table_rows_json.dart';
import 'table_focus_provider.dart';
import 'table_row_detail_provider.dart';
import 'table_row_selection_provider.dart';
import 'table_schema_provider.dart';
import 'resolved_collection_provider.dart';
import 'session_user_provider.dart';
import 'table_filter_provider.dart';
import 'toast_provider.dart';

/// Page size for table row list / infinite scroll requests.
const tableRowsPageSize = 100;

final class TableRowsData {
  const TableRowsData({
    required this.columns,
    required this.columnShapes,
    required this.rows,
    required this.total,
    required this.truncated,
    required this.sqliteName,
    this.schema,
    this.isLoadingMore = false,
  });

  final List<String> columns;
  final List<ColumnShape> columnShapes;
  final List<List<Object?>> rows;
  final int total;
  final bool truncated;
  final String sqliteName;
  final TableSchemaShape? schema;
  final bool isLoadingMore;
}

final tableRowsProvider = AsyncNotifierProvider<TableRowsNotifier, TableRowsData?>(
  TableRowsNotifier.new,
);

class TableRowsNotifier extends AsyncNotifier<TableRowsData?> {
  var _loadingMore = false;

  @override
  Future<TableRowsData?> build() async {
    final focus = ref.watch(tableFocusProvider);
    if (focus == null) return null;
    if (!ref.binding.isClient) return null;

    final schema = ref.watch(tableSchemaProvider);
    final where = ref.watch(tableAppliedWhereProvider);

    try {
      return await _loadTableRows(
        sqliteName: focus.sqliteName,
        schema: schema,
        where: where,
        limit: tableRowsPageSize,
        offset: 0,
      );
    } catch (e) {
      throw StateError('Failed to get table rows: $e');
    }
  }

  /// Fetches the next page and appends rows when the user scrolls near the end.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.truncated || _loadingMore) return;

    _loadingMore = true;
    state = AsyncData(
      TableRowsData(
        columns: current.columns,
        columnShapes: current.columnShapes,
        rows: current.rows,
        total: current.total,
        truncated: current.truncated,
        sqliteName: current.sqliteName,
        schema: current.schema,
        isLoadingMore: true,
      ),
    );

    try {
      final where = ref.read(tableFilterProvider).appliedWhere;
      final page = await _loadTableRows(
        sqliteName: current.sqliteName,
        schema: current.schema,
        where: where,
        limit: tableRowsPageSize,
        offset: current.rows.length,
      );
      final mergedRows = [...current.rows, ...page.rows];
      state = AsyncData(
        TableRowsData(
          columns: current.columns,
          columnShapes: current.columnShapes,
          rows: mergedRows,
          total: page.total,
          truncated: mergedRows.length < page.total,
          sqliteName: current.sqliteName,
          schema: current.schema,
        ),
      );
    } catch (e) {
      state = AsyncData(current);
      ref.read(toastProvider.notifier).showError(
        switch (e) {
          StateError(:final message) => message,
          _ => 'Failed to load more rows: $e',
        },
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// Rows matching [selection], fetching all pages when the whole table is selected.
  Future<List<List<Object?>>> rowsForSelection(TableRowSelectionState selection) async {
    final data = state.value;
    if (data == null || selection.isEmpty) return const [];

    if (selection.coversEntireTable) {
      final all = <List<Object?>>[];
      const pageSize = 500;
      while (true) {
        final where = ref.read(tableFilterProvider).appliedWhere;
        final page = await _fetchRowPage(
          sqliteName: data.sqliteName,
          columns: data.columns,
          columnShapes: data.columnShapes,
          where: where,
          offset: all.length,
          limit: pageSize,
        );
        all.addAll(page);
        if (page.length < pageSize) return all;
      }
    }

    return [
      for (final row in data.rows)
        if (selection.keys.contains(tableRowKey(row, data.columnShapes))) row,
    ];
  }

  /// Pretty-printed JSON array of the current row selection.
  Future<String> jsonForSelectedRows(TableRowSelectionState selection) async {
    final data = state.value;
    if (data == null || selection.isEmpty) return '[]';

    final rows = await rowsForSelection(selection);
    return encodeTableRowsAsJson(columns: data.columns, rows: rows);
  }

  /// Creates one row and reloads the table. Returns the created record map.
  Future<Map<String, Object?>> createRow({
    required String sqliteName,
    required Map<String, Object?> object,
  }) async {
    if (object.isEmpty) {
      throw StateError('No fields to create');
    }

    try {
      final created = await revaliServer.db.create(
        body: CreateBody(
          table: sqliteName,
          object: apiWireObject(object),
        ),
      );
      ref.invalidateSelf();
      return created;
    } catch (e) {
      throw StateError('Failed to create row: $e');
    }
  }

  /// Updates one row and reloads the table. Returns the updated record map.
  Future<Map<String, Object?>> updateRow({
    required String sqliteName,
    required List<Object?> row,
    required List<String> columns,
    required List<ColumnShape> columnShapes,
    required Map<String, Object?> changedFields,
  }) async {
    if (changedFields.isEmpty) {
      throw StateError('No fields to update');
    }

    final where = tableRowWhere(
      row: row,
      columns: columns,
      columnShapes: columnShapes,
    );
    if (where == null) {
      throw StateError('Cannot update row: incomplete primary key.');
    }

    try {
      final updated = await revaliServer.db.update(
        body: UpdateOneBody(
          table: sqliteName,
          where: where,
          updates: [ObjectUpdate(apiWireObject(changedFields))],
        ),
      );
      ref.invalidateSelf();
      return updated;
    } catch (e) {
      throw StateError('Failed to update row: $e');
    }
  }

  /// Deletes the current selection, then reloads the table.
  Future<void> deleteSelected(TableRowSelectionState selection) async {
    final data = state.value;
    if (data == null || selection.isEmpty) return;

    final allActions = ref.read(tableCollectionActionsProvider);
    final sessionCanEdit = ref.read(sessionUserProvider)?.canEdit == true;
    if (!canDeleteTableRows(
      allActions: allActions,
      actions: allActions[data.sqliteName],
      sessionCanEdit: sessionCanEdit,
      sqliteName: data.sqliteName,
      columnShapes: data.columnShapes,
    )) {
      throw StateError('Cannot delete rows: this table is read-only.');
    }

    try {
      if (selection.coversEntireTable) {
        await _deleteEntireTable(data);
      } else {
        await _deleteRowKeys(data, selection.keys, rows: data.rows);
      }
    } catch (e) {
      throw StateError('Failed to delete rows: $e');
    }

    ref.read(tableRowSelectionProvider.notifier).clear();
    ref.read(tableRowDetailProvider.notifier).close();
    ref.invalidateSelf();
  }

  Future<void> _deleteEntireTable(TableRowsData data) async {
    const pageSize = 500;
    while (true) {
      final where = ref.read(tableFilterProvider).appliedWhere;
      final page = await _fetchRowPage(
        sqliteName: data.sqliteName,
        columns: data.columns,
        columnShapes: data.columnShapes,
        where: where,
        offset: 0,
        limit: pageSize,
      );
      if (page.isEmpty) return;

      final keys = {
        for (final row in page) tableRowKey(row, data.columnShapes),
      };
      await _deleteRowKeys(data, keys, rows: page);
      if (page.length < pageSize) return;
    }
  }

  Future<List<List<Object?>>> _fetchRowPage({
    required String sqliteName,
    required List<String> columns,
    required List<ColumnShape> columnShapes,
    Where? where,
    required int offset,
    required int limit,
  }) async {
    final data = await revaliServer.db.list(
      body: ListBody(table: sqliteName, where: where, offset: offset, limit: limit),
    );
    final items = _parseListItems(data);
    return [
      for (final item in items) [for (final col in columns) item[col]],
    ];
  }

  Future<void> _deleteRowKeys(
    TableRowsData data,
    Set<String> keys, {
    required List<List<Object?>> rows,
  }) async {
    if (keys.isEmpty) return;

    final pkShapes = data.columnShapes.where((s) => s.isPrimaryKey).toList();
    if (pkShapes.isEmpty) {
      throw StateError('Cannot delete rows: table has no primary key.');
    }

    if (pkShapes.length == 1) {
      final pkName = pkShapes.single.name;
      final pkIndex = data.columns.indexOf(pkName);
      if (pkIndex < 0) {
        throw StateError('Cannot delete rows: primary key column missing from row data.');
      }
      final values = <Object>[
        for (final row in rows)
          if (keys.contains(tableRowKey(row, data.columnShapes))) row[pkIndex] as Object,
      ];
      if (values.isEmpty) return;

      await revaliServer.db.deleteMany(
        body: DeleteBody(
          table: data.sqliteName,
          where: In(pkName, values),
        ),
      );
      return;
    }

    for (final row in rows) {
      final key = tableRowKey(row, data.columnShapes);
      if (!keys.contains(key)) continue;
      final where = tableRowWhere(
        row: row,
        columns: data.columns,
        columnShapes: data.columnShapes,
      );
      if (where == null) {
        throw StateError('Cannot delete row: incomplete primary key.');
      }
      await revaliServer.db.delete(
        body: DeleteOneBody(table: data.sqliteName, where: where),
      );
    }
  }
}

Future<TableRowsData> _loadTableRows({
  required String sqliteName,
  required TableSchemaShape? schema,
  Where? where,
  int? limit,
  int? offset,
}) async {
  final data = await revaliServer.db.list(
    body: ListBody(table: sqliteName, where: where, limit: limit, offset: offset),
  );

  final items = _parseListItems(data);
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

List<Map<String, Object?>> _parseListItems(Map<String, Object?> data) {
  final itemsRaw = data['items'];
  if (itemsRaw is! List) {
    throw StateError('Invalid /db/list payload: missing items list');
  }

  return [
    for (final e in itemsRaw)
      {
        if (e is Map)
          for (final MapEntry(:key, :value) in e.entries) key.toString(): value as Object?,
      },
  ];
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
