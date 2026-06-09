import 'dart:convert';

import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../utils/table_where_build.dart';
import 'sqlite_tables_provider.dart';
import 'table_focus_provider.dart';
import 'table_row_detail_provider.dart';
import 'table_row_create_provider.dart';
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

final tableFilterProvider = NotifierProvider<TableFilterNotifier, TableFilterState>(TableFilterNotifier.new);

/// Applied server filter only — draft edits in the search panel do not notify this.
final tableAppliedWhereProvider = Provider<Where?>((ref) {
  return ref.watch(tableFilterProvider.select((state) => state.appliedWhere));
});

const _filterQueryParam = 'filter';

/// Set once in main() before Jaspr/router initialization so router redirects can't lose it.
String _initialSearch = '';

void captureInitialFilterSearch(String search) {
  _initialSearch = search;
}

Where? _whereFromUrl() {
  // Prefer the initial captured search (set before router redirects), fall back to current.
  final search = _initialSearch.isNotEmpty ? _initialSearch : web.window.location.search;
  try {
    if (search.isEmpty) return null;
    final params = Uri.splitQueryString(search.startsWith('?') ? search.substring(1) : search);
    final encoded = params[_filterQueryParam];
    if (encoded == null || encoded.isEmpty) return null;
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(encoded)))) as Map;
    return Where.fromJson(json);
  } catch (_) {
    return null;
  }
}

void _pushFilterUrl(Where? where) {
  final uri = Uri.parse(web.window.location.href);
  final params = Map<String, String>.from(uri.queryParameters);
  if (where == null) {
    params.remove(_filterQueryParam);
  } else {
    params[_filterQueryParam] = base64Url.encode(utf8.encode(jsonEncode(where.toJson())));
  }
  final updated = params.isEmpty
      ? '${uri.scheme}://${uri.authority}${uri.path}'
      : '${uri.scheme}://${uri.authority}${uri.path}?${Uri(queryParameters: params).query}';
  web.window.history.replaceState(null, '', updated);
}

class TableFilterNotifier extends Notifier<TableFilterState> {
  SqliteTableRef? _lastTable;

  @override
  TableFilterState build() {
    final table = ref.watch(tableFocusProvider);
    if (!ref.binding.isClient) return const TableFilterState();

    // Clear filter URL when navigating to a different table.
    if (_lastTable != null && _lastTable?.sqliteName != table?.sqliteName) {
      _initialSearch = ''; // discard old table's initial search
      _pushFilterUrl(null);
      _lastTable = table;
      return const TableFilterState();
    }
    _lastTable = table;

    // _whereFromUrl prefers _initialSearch (captured before router redirect) over
    // window.location.search. _initialSearch stays set until apply/clear/table-change
    // so repeated build() calls (tableFocusProvider emitting same table) are stable.
    final where = _whereFromUrl();
    if (where == null) return const TableFilterState();
    return TableFilterState(
      appliedWhere: where,
      draftRows: draftsFromWhere(where),
      combine: combineFromWhere(where),
    );
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
    ref.read(tableRowCreateProvider.notifier).close();
    state = state.copyWith(panelOpen: true, draftRows: _seedDraftRows(state.draftRows));
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
    state = state.copyWith(draftRows: [...state.draftRows, defaultFilterConditionDraft(shapes)]);
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

    final result = buildWhereFromDraft(rows: state.draftRows, combine: state.combine, columnShapes: shapes);

    switch (result) {
      case TableWhereBuildError(:final message):
        ref.read(toastProvider.notifier).showError(message);
        return false;
      case TableWhereBuildSuccess(:final where):
        _clearRowUiState();
        _initialSearch = ''; // user took over; stop using the captured initial search
        state = state.copyWith(appliedWhere: where);
        if (ref.binding.isClient) _pushFilterUrl(where);
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
    _initialSearch = ''; // user took over; stop using the captured initial search
    state = const TableFilterState();
    if (ref.binding.isClient) _pushFilterUrl(null);
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
    state = state.copyWith(panelOpen: true, draftRows: draftsFromWhere(applied), combine: combineFromWhere(applied));
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
