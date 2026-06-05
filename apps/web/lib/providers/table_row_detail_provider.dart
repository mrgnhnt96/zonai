import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import 'table_focus_provider.dart';
import 'table_row_create_provider.dart';

enum TableRowDetailViewMode { fields, json, edit }

/// Previous row state restored by [TableRowDetailNotifier.pop].
final class TableRowDetailSnapshot {
  const TableRowDetailSnapshot({
    required this.rowKey,
    required this.row,
    required this.columns,
    required this.columnShapes,
    required this.sqliteName,
    required this.viewMode,
    required this.openedViaEditShortcut,
  });

  final String rowKey;
  final List<Object?> row;
  final List<String> columns;
  final List<ColumnShape> columnShapes;
  final String sqliteName;
  final TableRowDetailViewMode viewMode;
  final bool openedViaEditShortcut;
}

final class TableRowDetailState {
  const TableRowDetailState({
    required this.rowKey,
    required this.row,
    required this.columns,
    required this.columnShapes,
    required this.sqliteName,
    this.viewMode = TableRowDetailViewMode.fields,
    this.openedViaEditShortcut = false,
    this.backStack = const [],
  });

  final String rowKey;
  final List<Object?> row;
  final List<String> columns;
  final List<ColumnShape> columnShapes;
  final String sqliteName;
  final TableRowDetailViewMode viewMode;

  /// True when the panel was opened straight into edit via the `e` shortcut.
  final bool openedViaEditShortcut;

  /// Rows navigated from via FK "view reference" in the detail panel.
  final List<TableRowDetailSnapshot> backStack;

  bool get canNavigateBack => backStack.isNotEmpty;

  TableRowDetailState copyWith({
    List<Object?>? row,
    TableRowDetailViewMode? viewMode,
    bool? openedViaEditShortcut,
    List<TableRowDetailSnapshot>? backStack,
  }) {
    return TableRowDetailState(
      rowKey: rowKey,
      row: row ?? this.row,
      sqliteName: sqliteName,
      columns: columns,
      columnShapes: columnShapes,
      viewMode: viewMode ?? this.viewMode,
      openedViaEditShortcut: openedViaEditShortcut ?? this.openedViaEditShortcut,
      backStack: backStack ?? this.backStack,
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

  TableRowDetailSnapshot _snapshot(TableRowDetailState current) {
    return TableRowDetailSnapshot(
      rowKey: current.rowKey,
      row: List<Object?>.from(current.row),
      sqliteName: current.sqliteName,
      columns: current.columns,
      columnShapes: current.columnShapes,
      viewMode: current.viewMode,
      openedViaEditShortcut: current.openedViaEditShortcut,
    );
  }

  TableRowDetailState _stateFromSnapshot(
    TableRowDetailSnapshot snapshot, {
    required List<TableRowDetailSnapshot> backStack,
  }) {
    return TableRowDetailState(
      rowKey: snapshot.rowKey,
      row: List<Object?>.from(snapshot.row),
      sqliteName: snapshot.sqliteName,
      columns: snapshot.columns,
      columnShapes: snapshot.columnShapes,
      viewMode: snapshot.viewMode,
      openedViaEditShortcut: snapshot.openedViaEditShortcut,
      backStack: backStack,
    );
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
    ref.read(tableRowCreateProvider.notifier).close();
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

  void pushReferencedRow({
    required String rowKey,
    required List<Object?> row,
    required String sqliteName,
    required List<String> columns,
    required List<ColumnShape> columnShapes,
  }) {
    final current = state;
    if (current == null) {
      open(
        rowKey: rowKey,
        row: row,
        sqliteName: sqliteName,
        columns: columns,
        columnShapes: columnShapes,
      );
      return;
    }
    state = TableRowDetailState(
      rowKey: rowKey,
      row: List<Object?>.from(row),
      sqliteName: sqliteName,
      columns: columns,
      columnShapes: columnShapes,
      backStack: [...current.backStack, _snapshot(current)],
    );
  }

  void pop() {
    final current = state;
    if (current == null || current.backStack.isEmpty) return;
    final stack = current.backStack;
    final previous = stack.last;
    state = _stateFromSnapshot(previous, backStack: stack.sublist(0, stack.length - 1));
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
    if (current != null && current.rowKey == rowKey) {
      if (current.viewMode == viewMode &&
          !(viaEditShortcut && viewMode == TableRowDetailViewMode.edit)) {
        return;
      }
      state = current.copyWith(
        viewMode: viewMode,
        openedViaEditShortcut: viaEditShortcut && viewMode == TableRowDetailViewMode.edit
            ? true
            : current.openedViaEditShortcut,
      );
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
