import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import 'table_focus_provider.dart';

final class TableSortState {
  const TableSortState({required this.columnName, required this.ascending});

  final String columnName;
  final bool ascending;
}

final tableSortProvider = NotifierProvider<TableSortNotifier, TableSortState?>(
  TableSortNotifier.new,
);

class TableSortNotifier extends Notifier<TableSortState?> {
  @override
  TableSortState? build() {
    ref.watch(tableFocusProvider);
    return null;
  }

  void toggleColumn(String columnName) {
    final current = state;
    if (current?.columnName == columnName) {
      state = current!.ascending
          ? TableSortState(columnName: columnName, ascending: false)
          : null;
    } else {
      state = TableSortState(columnName: columnName, ascending: true);
    }
  }
}

final class TableSortTooltipState {
  const TableSortTooltipState({this.text, this.top = 0, this.left = 0});

  final String? text;
  final double top;
  final double left;
}

final tableSortTooltipProvider = NotifierProvider<TableSortTooltipNotifier, TableSortTooltipState>(
  TableSortTooltipNotifier.new,
);

class TableSortTooltipNotifier extends Notifier<TableSortTooltipState> {
  @override
  TableSortTooltipState build() {
    ref.watch(tableFocusProvider);
    return const TableSortTooltipState();
  }

  void show({required String text, required double top, required double left}) {
    state = TableSortTooltipState(text: text, top: top, left: left);
  }

  void hide() {
    if (state.text != null) {
      state = const TableSortTooltipState();
    }
  }
}
