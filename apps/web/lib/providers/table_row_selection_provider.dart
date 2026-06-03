import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import 'table_focus_provider.dart';

final class TableRowSelectionState {
  const TableRowSelectionState({
    this.keys = const {},
    this.coversEntireTable = false,
  });

  final Set<String> keys;
  final bool coversEntireTable;

  bool get isEmpty => keys.isEmpty && !coversEntireTable;

  int displayCount(int tableTotal) => coversEntireTable ? tableTotal : keys.length;

  bool isSelected(String key) => coversEntireTable || keys.contains(key);
}

final tableRowSelectionProvider = NotifierProvider<TableRowSelectionNotifier, TableRowSelectionState>(
  TableRowSelectionNotifier.new,
);

class TableRowSelectionNotifier extends Notifier<TableRowSelectionState> {
  @override
  TableRowSelectionState build() {
    ref.watch(tableFocusProvider);
    return const TableRowSelectionState();
  }

  void toggle(String key) {
    setSelected(key, selected: !state.isSelected(key));
  }

  void setSelected(String key, {required bool selected, Iterable<String>? pageKeys}) {
    if (!selected && state.coversEntireTable && pageKeys != null) {
      state = TableRowSelectionState(
        keys: pageKeys.where((k) => k != key).toSet(),
      );
      return;
    }

    if (state.coversEntireTable && selected) return;

    final next = Set<String>.from(state.keys);
    if (selected) {
      if (next.contains(key)) return;
      next.add(key);
    } else {
      if (!next.contains(key)) return;
      next.remove(key);
    }
    state = TableRowSelectionState(keys: next);
  }

  void setAll(Iterable<String> keys, {required bool selected}) {
    if (!selected) {
      if (state.isEmpty) return;
      state = const TableRowSelectionState();
      return;
    }
    state = TableRowSelectionState(keys: Set<String>.from(keys));
  }

  void selectEntireTable() {
    if (state.coversEntireTable) return;
    state = TableRowSelectionState(
      keys: state.keys,
      coversEntireTable: true,
    );
  }

  void clear() {
    if (state.isEmpty) return;
    state = const TableRowSelectionState();
  }
}
