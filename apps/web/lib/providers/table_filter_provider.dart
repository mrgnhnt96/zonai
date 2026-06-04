import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../utils/table_where_build.dart';
import 'table_focus_provider.dart';
import 'table_row_detail_provider.dart';
import 'table_row_selection_provider.dart';
import 'table_rows_provider.dart';
import 'table_schema_provider.dart';
import 'toast_provider.dart';

final class TableFilterState {
  const TableFilterState({
    this.panelOpen = false,
    this.draftRows = const [FilterConditionDraft()],
    this.combine = FilterCombine.and,
    this.appliedWhere,
  });

  final bool panelOpen;
  final List<FilterConditionDraft> draftRows;
  final FilterCombine combine;
  final Where? appliedWhere;

  bool get hasAppliedFilter => appliedWhere != null;

  TableFilterState copyWith({
    bool? panelOpen,
    List<FilterConditionDraft>? draftRows,
    FilterCombine? combine,
    Where? appliedWhere,
    bool clearAppliedWhere = false,
  }) {
    return TableFilterState(
      panelOpen: panelOpen ?? this.panelOpen,
      draftRows: draftRows ?? this.draftRows,
      combine: combine ?? this.combine,
      appliedWhere: clearAppliedWhere ? null : (appliedWhere ?? this.appliedWhere),
    );
  }
}

final tableFilterProvider = NotifierProvider<TableFilterNotifier, TableFilterState>(
  TableFilterNotifier.new,
);

/// Applied server filter only — draft edits in the search panel do not notify this.
final tableAppliedWhereProvider = Provider<Where?>((ref) {
  return ref.watch(tableFilterProvider.select((state) => state.appliedWhere));
});

class TableFilterNotifier extends Notifier<TableFilterState> {
  @override
  TableFilterState build() {
    ref.watch(tableFocusProvider);
    return const TableFilterState();
  }

  void togglePanel() {
    if (state.panelOpen) {
      closePanel();
    } else {
      openPanel();
    }
  }

  void setPanelOpen(bool open) {
    if (open) {
      openPanel();
    } else {
      closePanel();
    }
  }

  void openPanel() {
    ref.read(tableRowDetailProvider.notifier).close();
    state = state.copyWith(
      panelOpen: true,
      draftRows: _seedDraftRows(state.draftRows),
    );
  }

  void closePanel() {
    if (!state.panelOpen) return;
    state = state.copyWith(panelOpen: false);
  }

  void setCombine(FilterCombine combine) {
    state = state.copyWith(combine: combine);
  }

  void updateRow(int index, FilterConditionDraft row) {
    final rows = [...state.draftRows];
    if (index < 0 || index >= rows.length) return;
    rows[index] = row;
    state = state.copyWith(draftRows: rows);
  }

  void addRow() {
    final shapes = _columnShapes();
    state = state.copyWith(
      draftRows: [...state.draftRows, defaultFilterConditionDraft(shapes)],
    );
  }

  void removeRow(int index) {
    final rows = [...state.draftRows];
    if (index < 0 || index >= rows.length) return;
    if (rows.length == 1) {
      state = state.copyWith(draftRows: [defaultFilterConditionDraft(_columnShapes())]);
      return;
    }
    rows.removeAt(index);
    state = state.copyWith(draftRows: rows);
  }

  /// Validates draft, applies server filter, and reloads rows.
  bool apply() {
    final schema = ref.read(tableSchemaProvider);
    final shapes = schema?.columns ?? const <ColumnShape>[];
    if (shapes.isEmpty) {
      ref.read(toastProvider.notifier).showError('Load the table schema before filtering.');
      return false;
    }

    final result = buildWhereFromDraft(
      rows: state.draftRows,
      combine: state.combine,
      columnShapes: shapes,
    );

    switch (result) {
      case TableWhereBuildError(:final message):
        ref.read(toastProvider.notifier).showError(message);
        return false;
      case TableWhereBuildSuccess(:final where):
        _clearRowUiState();
        state = state.copyWith(appliedWhere: where);
        ref.invalidate(tableRowsProvider);
        return true;
    }
  }

  void clear() {
    if (!state.hasAppliedFilter && state.draftRows.length == 1 && state.draftRows.first.columnName.isEmpty) {
      state = state.copyWith(panelOpen: false);
      return;
    }
    _clearRowUiState();
    state = const TableFilterState();
    ref.invalidate(tableRowsProvider);
  }

  /// Opens panel and restores draft from the active filter when re-editing.
  void openForEdit() {
    final applied = state.appliedWhere;
    if (applied == null) {
      openPanel();
      return;
    }

    ref.read(tableRowDetailProvider.notifier).close();
    state = state.copyWith(
      panelOpen: true,
      draftRows: draftsFromWhere(applied),
      combine: combineFromWhere(applied),
    );
  }

  void _clearRowUiState() {
    ref.read(tableRowSelectionProvider.notifier).clear();
    ref.read(tableRowDetailProvider.notifier).close();
  }

  List<ColumnShape> _columnShapes() => ref.read(tableSchemaProvider)?.columns ?? const [];

  List<FilterConditionDraft> _seedDraftRows(List<FilterConditionDraft> rows) {
    final shapes = _columnShapes();
    if (shapes.isEmpty) return rows;
    return [for (final row in rows) ensureDraftDefaults(row, shapes)];
  }
}
