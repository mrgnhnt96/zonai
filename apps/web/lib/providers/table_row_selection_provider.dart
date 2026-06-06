import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import 'table_focus_provider.dart';

final class TableRowSelectionState {
  const TableRowSelectionState({this.keys = const {}, this.coversEntireTable = false});

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
  int? _anchorIndex;
  bool _shiftClick = false;

  @override
  TableRowSelectionState build() {
    ref.watch(tableFocusProvider);
    _anchorIndex = null;
    _shiftClick = false;
    return const TableRowSelectionState();
  }

  /// Call from the row checkbox `click` handler before `onChange` runs.
  void noteCheckboxClick(web.Event event) {
    _shiftClick = event is web.MouseEvent && event.shiftKey;
  }

  void handleRowCheckboxChange({
    required int index,
    required String key,
    required bool selected,
    required List<String> pageKeys,
    bool shiftKey = false,
  }) {
    final shiftSelect = shiftKey || _shiftClick;
    if (shiftSelect && _anchorIndex != null) {
      setSelectedRange(fromIndex: _anchorIndex!, toIndex: index, selected: selected, pageKeys: pageKeys);
    } else {
      setSelected(key, selected: selected, pageKeys: pageKeys);
    }
    _anchorIndex = index;
    _shiftClick = false;
  }

  void setSelectedRange({
    required int fromIndex,
    required int toIndex,
    required bool selected,
    required List<String> pageKeys,
  }) {
    final start = fromIndex < toIndex ? fromIndex : toIndex;
    final end = fromIndex < toIndex ? toIndex : fromIndex;
    final rangeKeys = pageKeys.sublist(start, end + 1);

    if (!selected && state.coversEntireTable) {
      state = TableRowSelectionState(keys: pageKeys.toSet().difference(rangeKeys.toSet()));
      return;
    }

    if (state.coversEntireTable && selected) return;

    final next = Set<String>.from(state.keys);
    for (final rangeKey in rangeKeys) {
      if (selected) {
        next.add(rangeKey);
      } else {
        next.remove(rangeKey);
      }
    }
    state = TableRowSelectionState(keys: next);
  }

  void toggle(String key) {
    setSelected(key, selected: !state.isSelected(key));
  }

  void setSelected(String key, {required bool selected, Iterable<String>? pageKeys}) {
    if (!selected && state.coversEntireTable && pageKeys != null) {
      state = TableRowSelectionState(keys: pageKeys.where((k) => k != key).toSet());
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
    state = TableRowSelectionState(keys: state.keys, coversEntireTable: true);
  }

  void clear() {
    if (state.isEmpty) return;
    state = const TableRowSelectionState();
  }
}
