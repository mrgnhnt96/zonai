import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_web/utils/navigable_sidebar_tables.dart';
import 'package:zonai_web/utils/sqlite_table_utils.dart';

import 'home_ui_provider.dart';
import 'sqlite_tables_provider.dart';
import 'table_focus_provider.dart';
import 'table_sort_provider.dart';

enum HomeKeyboardFocusZone { tableRows, sidebar }

String sidebarTableItemId(String sqliteName) => 'home-sidebar-table-$sqliteName';

final class TableRowKeyboardFocusState {
  const TableRowKeyboardFocusState({
    this.rowKey,
    this.zone = HomeKeyboardFocusZone.tableRows,
    this.sidebarTableSqliteName,
  });

  final String? rowKey;
  final HomeKeyboardFocusZone zone;

  /// Keyboard-highlighted sidebar table (not necessarily the active route).
  final String? sidebarTableSqliteName;
}

final tableRowKeyboardFocusProvider =
    NotifierProvider<TableRowKeyboardFocusNotifier, TableRowKeyboardFocusState>(
  TableRowKeyboardFocusNotifier.new,
);

class TableRowKeyboardFocusNotifier extends Notifier<TableRowKeyboardFocusState> {
  final Map<String, String> _rowKeyByTable = {};
  var _zone = HomeKeyboardFocusZone.tableRows;
  String? _sidebarTableSqliteName;

  @override
  TableRowKeyboardFocusState build() {
    ref.watch(tableFocusProvider);
    ref.watch(tableSortProvider);
    return TableRowKeyboardFocusState(
      zone: _zone,
      sidebarTableSqliteName: _sidebarTableSqliteName,
    );
  }

  void _publish({String? rowKey}) {
    state = TableRowKeyboardFocusState(
      rowKey: rowKey,
      zone: _zone,
      sidebarTableSqliteName: _sidebarTableSqliteName,
    );
  }

  List<SqliteTableRef> _navigableTables() {
    final tablesSnapshot = ref.read(sqliteTablesProvider);
    final ui = ref.read(homeUiProvider);
    final routeFocused = ref.read(tableFocusProvider);
    return navigableSidebarTables(
      allTables: tablesSnapshot.tables,
      routeFocused: routeFocused,
      sidebarVisuallyCollapsed: ui.sidebarVisuallyCollapsed,
      systemTablesExpanded: ui.systemTablesExpanded,
    );
  }

  void _scrollSidebarTableIntoView(String sqliteName) {
    if (!ref.binding.isClient) return;
    final ui = ref.read(homeUiProvider);
    final regionClass = ui.sidebarVisuallyCollapsed ? 'home-sidebar-rail' : 'home-sidebar-body';
    final scrollEl = web.document.querySelector('.$regionClass');
    final item = web.document.getElementById(sidebarTableItemId(sqliteName));
    if (scrollEl == null || item == null) return;
    item.scrollIntoView(web.ScrollIntoViewOptions(block: 'nearest'));
  }

  void rememberRowForTable(String tableSqliteName, String? rowKey) {
    if (rowKey != null) {
      _rowKeyByTable[tableSqliteName] = rowKey;
    }
  }

  void focusRowKey(String? rowKey, {String? tableSqliteName}) {
    if (tableSqliteName != null) {
      rememberRowForTable(tableSqliteName, rowKey);
    }
    if (state.rowKey == rowKey && _zone == HomeKeyboardFocusZone.tableRows) return;
    _zone = HomeKeyboardFocusZone.tableRows;
    _publish(rowKey: rowKey);
  }

  void focusIndex(int index, List<String> pageKeys, {required String tableSqliteName}) {
    if (pageKeys.isEmpty) {
      clear();
      return;
    }
    final clamped = index.clamp(0, pageKeys.length - 1);
    focusRowKey(pageKeys[clamped], tableSqliteName: tableSqliteName);
  }

  void moveBy(int delta, List<String> pageKeys, {required String tableSqliteName}) {
    if (pageKeys.isEmpty) return;
    final current = state.rowKey;
    if (current == null) {
      focusIndex(delta >= 0 ? 0 : pageKeys.length - 1, pageKeys, tableSqliteName: tableSqliteName);
      return;
    }
    final index = pageKeys.indexOf(current);
    if (index < 0) {
      focusIndex(delta >= 0 ? 0 : pageKeys.length - 1, pageKeys, tableSqliteName: tableSqliteName);
      return;
    }
    focusIndex(index + delta, pageKeys, tableSqliteName: tableSqliteName);
  }

  void clear() {
    if (state.rowKey == null && _zone == HomeKeyboardFocusZone.tableRows) return;
    _zone = HomeKeyboardFocusZone.tableRows;
    _publish(rowKey: null);
  }

  void enterSidebar({required String tableSqliteName, String? currentRowKey}) {
    rememberRowForTable(tableSqliteName, currentRowKey);
    _sidebarTableSqliteName = tableSqliteName;
    _zone = HomeKeyboardFocusZone.sidebar;
    _publish(rowKey: state.rowKey);
    _scrollSidebarTableIntoView(tableSqliteName);
  }

  void exitToTableRows({required String tableSqliteName, required List<String> pageKeys}) {
    final saved = _rowKeyByTable[tableSqliteName];
    String? rowKey;
    if (saved != null && pageKeys.contains(saved)) {
      rowKey = saved;
    } else if (pageKeys.isNotEmpty) {
      rowKey = pageKeys.first;
    }
    _zone = HomeKeyboardFocusZone.tableRows;
    _publish(rowKey: rowKey);
  }

  void moveSidebarTableBy(int delta) {
    final tables = _navigableTables();
    if (tables.isEmpty) return;

    var index = _sidebarTableSqliteName == null
        ? 0
        : tables.indexWhere((t) => t.sqliteName == _sidebarTableSqliteName);
    if (index < 0) index = 0;
    final nextIndex = (index + delta).clamp(0, tables.length - 1);
    if (nextIndex == index) return;

    final table = tables[nextIndex];
    if (isSystemSqliteTable(table.sqliteName)) {
      ref.read(homeUiProvider.notifier).setSystemTablesExpanded(true);
    }
    _sidebarTableSqliteName = table.sqliteName;
    _publish(rowKey: state.rowKey);
    _scrollSidebarTableIntoView(table.sqliteName);
  }

  void selectSidebarTable(BuildContext context) {
    final sqlite = _sidebarTableSqliteName;
    if (sqlite == null) return;

    SqliteTableRef? table;
    for (final t in ref.read(sqliteTablesProvider).tables) {
      if (t.sqliteName == sqlite) {
        table = t;
        break;
      }
    }
    if (table == null) return;

    if (isSystemSqliteTable(table.sqliteName)) {
      ref.read(homeUiProvider.notifier).setSystemTablesExpanded(true);
    }
    ref.read(homeUiProvider.notifier).captureSidebarScrollFromDom();
    ref.read(homeUiProvider.notifier).closeMobileNav();
    ref.read(tableFocusProvider.notifier).setFocused(context, table);
  }
}
