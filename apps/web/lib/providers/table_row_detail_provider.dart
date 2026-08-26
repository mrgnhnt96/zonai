import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import 'pending_row_detail_provider.dart';
import 'sqlite_tables_provider.dart';
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

/// The detail state a pending row opens as, or null when it is not for
/// [focus].
///
/// A pending row is only ever opened on its own table's route. Opening it
/// anywhere else would render a row from one collection inside another
/// collection's panel, where every row action — edit, delete, reset password —
/// is authorised against the focused collection.
TableRowDetailState? pendingRowDetailState({required SqliteTableRef? focus, required PendingRowDetail? pending}) {
  if (pending == null || focus == null) return null;
  if (focus.sqliteName != pending.sqliteName) return null;

  return TableRowDetailState(
    rowKey: pending.rowKey,
    row: List<Object?>.from(pending.row),
    sqliteName: pending.sqliteName,
    columns: pending.columns,
    columnShapes: pending.columnShapes,
  );
}

final tableRowDetailProvider = NotifierProvider<TableRowDetailNotifier, TableRowDetailState?>(
  TableRowDetailNotifier.new,
);

class TableRowDetailNotifier extends Notifier<TableRowDetailState?> {
  /// Null on every rebuild but one: the rebuild a table focus change causes
  /// while a row is waiting in [pendingRowDetailProvider] for that very table.
  ///
  /// See [PendingRowDetail] for why a caller on another screen cannot simply
  /// call [open] and navigate.
  @override
  TableRowDetailState? build() {
    final focus = ref.watch(tableFocusProvider);
    // `read`, not `watch`: consuming a pending row clears it, and a watch
    // would make that clear a second rebuild — one that closes the panel the
    // row was just opened in.
    final pending = ref.read(pendingRowDetailProvider);
    if (pending == null) return null;

    final opened = pendingRowDetailState(focus: focus, pending: pending);
    if (opened == null) return null;

    // Cleared a turn later rather than here: Riverpod refuses a provider that
    // mutates another provider during its own build.
    final pendingNotifier = ref.read(pendingRowDetailProvider.notifier);
    Future.microtask(() => pendingNotifier.clearIf(pending));
    return opened;
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
      open(rowKey: rowKey, row: row, sqliteName: sqliteName, columns: columns, columnShapes: columnShapes);
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
    open(rowKey: rowKey, row: row, sqliteName: sqliteName, columns: columns, columnShapes: columnShapes);
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
      if (current.viewMode == viewMode && !(viaEditShortcut && viewMode == TableRowDetailViewMode.edit)) {
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
