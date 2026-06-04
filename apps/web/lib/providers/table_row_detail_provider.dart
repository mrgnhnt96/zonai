import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import 'table_focus_provider.dart';

final class TableRowDetailState {
  const TableRowDetailState({
    required this.rowKey,
    required this.row,
    required this.columns,
    required this.columnShapes,
  });

  final String rowKey;
  final List<Object?> row;
  final List<String> columns;
  final List<ColumnShape> columnShapes;
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
    required List<String> columns,
    required List<ColumnShape> columnShapes,
  }) {
    state = TableRowDetailState(
      rowKey: rowKey,
      row: List<Object?>.from(row),
      columns: columns,
      columnShapes: columnShapes,
    );
  }

  void close() {
    if (state == null) return;
    state = null;
  }

  void toggle({
    required String rowKey,
    required List<Object?> row,
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
      columns: columns,
      columnShapes: columnShapes,
    );
  }
}

final class TableRowDetailCopyTooltipState {
  const TableRowDetailCopyTooltipState({this.text, this.top = 0, this.left = 0});

  final String? text;
  final double top;
  final double left;
}

final tableRowDetailCopyTooltipProvider =
    NotifierProvider<TableRowDetailCopyTooltipNotifier, TableRowDetailCopyTooltipState>(
  TableRowDetailCopyTooltipNotifier.new,
);

class TableRowDetailCopyTooltipNotifier extends Notifier<TableRowDetailCopyTooltipState> {
  @override
  TableRowDetailCopyTooltipState build() {
    ref.watch(tableRowDetailProvider);
    return const TableRowDetailCopyTooltipState();
  }

  void show({required String text, required double top, required double left}) {
    state = TableRowDetailCopyTooltipState(text: text, top: top, left: left);
  }

  void hide() {
    if (state.text != null) {
      state = const TableRowDetailCopyTooltipState();
    }
  }
}
