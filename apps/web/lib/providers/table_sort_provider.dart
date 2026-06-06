import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import 'table_focus_provider.dart';

final class TableSortState {
  const TableSortState({required this.columnName, required this.ascending});

  final String columnName;
  final bool ascending;
}

final tableSortProvider = NotifierProvider<TableSortNotifier, TableSortState?>(TableSortNotifier.new);

class TableSortNotifier extends Notifier<TableSortState?> {
  @override
  TableSortState? build() {
    ref.watch(tableFocusProvider);
    return null;
  }

  void toggleColumn(String columnName) {
    final current = state;
    if (current?.columnName == columnName) {
      state = current!.ascending ? TableSortState(columnName: columnName, ascending: false) : null;
    } else {
      state = TableSortState(columnName: columnName, ascending: true);
    }
  }
}
