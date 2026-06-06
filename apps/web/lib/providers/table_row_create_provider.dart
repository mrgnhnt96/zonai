import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import 'table_filter_provider.dart';
import 'table_focus_provider.dart';
import 'table_row_detail_provider.dart';

final class TableRowCreateState {
  const TableRowCreateState({
    required this.sqliteName,
    required this.columns,
    required this.columnShapes,
    this.closeRequested = false,
  });

  final String sqliteName;
  final List<String> columns;
  final List<ColumnShape> columnShapes;

  /// Set when the header toggle (or other external control) asks to close the panel.
  final bool closeRequested;

  TableRowCreateState copyWith({bool? closeRequested}) {
    return TableRowCreateState(
      sqliteName: sqliteName,
      columns: columns,
      columnShapes: columnShapes,
      closeRequested: closeRequested ?? this.closeRequested,
    );
  }
}

final tableRowCreateProvider = NotifierProvider<TableRowCreateNotifier, TableRowCreateState?>(
  TableRowCreateNotifier.new,
);

class TableRowCreateNotifier extends Notifier<TableRowCreateState?> {
  @override
  TableRowCreateState? build() {
    ref.watch(tableFocusProvider);
    return null;
  }

  void open({required String sqliteName, required List<String> columns, required List<ColumnShape> columnShapes}) {
    ref.read(tableRowDetailProvider.notifier).close();
    ref.read(tableFilterProvider.notifier).closePanel();
    state = TableRowCreateState(sqliteName: sqliteName, columns: columns, columnShapes: columnShapes);
  }

  void close() {
    if (state == null) return;
    state = null;
  }

  /// Asks the create panel to close (shows discard prompt when there are unsaved changes).
  void requestClose() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(closeRequested: true);
  }

  void clearCloseRequest() {
    final current = state;
    if (current == null || !current.closeRequested) return;
    state = current.copyWith(closeRequested: false);
  }

  void toggle({required String sqliteName, required List<String> columns, required List<ColumnShape> columnShapes}) {
    if (state != null) {
      requestClose();
      return;
    }
    open(sqliteName: sqliteName, columns: columns, columnShapes: columnShapes);
  }
}
