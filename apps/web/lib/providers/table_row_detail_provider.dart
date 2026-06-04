import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import 'table_focus_provider.dart';

enum TableRowDetailViewMode { fields, json, edit }

final class TableRowDetailState {
  const TableRowDetailState({
    required this.rowKey,
    required this.row,
    required this.columns,
    required this.columnShapes,
    required this.sqliteName,
    this.viewMode = TableRowDetailViewMode.fields,
    this.openedViaEditShortcut = false,
  });

  final String rowKey;
  final List<Object?> row;
  final List<String> columns;
  final List<ColumnShape> columnShapes;
  final String sqliteName;
  final TableRowDetailViewMode viewMode;

  /// True when the panel was opened straight into edit via the `e` shortcut.
  final bool openedViaEditShortcut;

  TableRowDetailState copyWith({
    List<Object?>? row,
    TableRowDetailViewMode? viewMode,
    bool? openedViaEditShortcut,
  }) {
    return TableRowDetailState(
      rowKey: rowKey,
      row: row ?? this.row,
      sqliteName: sqliteName,
      columns: columns,
      columnShapes: columnShapes,
      viewMode: viewMode ?? this.viewMode,
      openedViaEditShortcut: openedViaEditShortcut ?? this.openedViaEditShortcut,
    );
  }
}

final tableRowDetailProvider = NotifierProvider<TableRowDetailNotifier, TableRowDetailState?>(
  TableRowDetailNotifier.new,
);

class TableRowDetailNotifier extends Notifier<TableRowDetailState?> {
  @override
  TableRowDetailState? build() {
    ref.watch(tableFocusProvider);
    return null;
  }

  void open({
    required String rowKey,
    required List<Object?> row,
    required String sqliteName,
    required List<String> columns,
    required List<ColumnShape> columnShapes,
    TableRowDetailViewMode viewMode = TableRowDetailViewMode.fields,
    bool viaEditShortcut = false,
  }) {
    state = TableRowDetailState(
      rowKey: rowKey,
      row: List<Object?>.from(row),
      sqliteName: sqliteName,
      columns: columns,
      columnShapes: columnShapes,
      viewMode: viewMode,
      openedViaEditShortcut: viaEditShortcut && viewMode == TableRowDetailViewMode.edit,
    );
  }

  void setViewMode(TableRowDetailViewMode viewMode) {
    final current = state;
    if (current == null || current.viewMode == viewMode) return;
    state = current.copyWith(viewMode: viewMode);
  }

  void replaceRow(List<Object?> row) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(row: List<Object?>.from(row));
  }

  void close() {
    if (state == null) return;
    state = null;
  }

  void toggle({
    required String rowKey,
    required List<Object?> row,
    required String sqliteName,
    required List<String> columns,
    required List<ColumnShape> columnShapes,
  }) {
    if (state?.rowKey == rowKey) {
      close();
      return;
    }
    open(
      rowKey: rowKey,
      row: row,
      sqliteName: sqliteName,
      columns: columns,
      columnShapes: columnShapes,
    );
  }

  void openFocusedRow({
    required String rowKey,
    required List<Object?> row,
    required String sqliteName,
    required List<String> columns,
    required List<ColumnShape> columnShapes,
    TableRowDetailViewMode viewMode = TableRowDetailViewMode.fields,
    bool viaEditShortcut = false,
  }) {
    final current = state;
    if (current?.rowKey == rowKey) {
      setViewMode(viewMode);
      return;
    }
    open(
      rowKey: rowKey,
      row: row,
      sqliteName: sqliteName,
      columns: columns,
      columnShapes: columnShapes,
      viewMode: viewMode,
      viaEditShortcut: viaEditShortcut,
    );
  }
}
