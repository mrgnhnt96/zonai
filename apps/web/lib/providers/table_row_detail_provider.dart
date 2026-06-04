import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import 'table_focus_provider.dart';

final class TableRowDetailState {
  const TableRowDetailState({
    required this.rowKey,
    required this.row,
    required this.columns,
    required this.columnShapes,
    required this.sqliteName,
  });

  final String rowKey;
  final List<Object?> row;
  final List<String> columns;
  final List<ColumnShape> columnShapes;
  final String sqliteName;
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
  }) {
    state = TableRowDetailState(
      rowKey: rowKey,
      row: List<Object?>.from(row),
      sqliteName: sqliteName,
      columns: columns,
      columnShapes: columnShapes,
    );
  }

  void replaceRow(List<Object?> row) {
    final current = state;
    if (current == null) return;
    state = TableRowDetailState(
      rowKey: current.rowKey,
      row: List<Object?>.from(row),
      sqliteName: current.sqliteName,
      columns: current.columns,
      columnShapes: current.columnShapes,
    );
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
}
