import '../providers/sqlite_tables_provider.dart';
import 'sqlite_table_utils.dart';

/// Sidebar table order for keyboard navigation (expanded body or collapsed rail).
List<SqliteTableRef> navigableSidebarTables({
  required List<SqliteTableRef> allTables,
  required SqliteTableRef? routeFocused,
  required bool sidebarVisuallyCollapsed,
  required bool systemTablesExpanded,
}) {
  final userTables = [
    for (final t in allTables)
      if (!isSystemSqliteTable(t.sqliteName)) t,
  ];
  final systemTables = [
    for (final t in allTables)
      if (isSystemSqliteTable(t.sqliteName)) t,
  ];

  if (sidebarVisuallyCollapsed) {
    return [
      ...userTables,
      if (routeFocused != null &&
          isSystemSqliteTable(routeFocused.sqliteName) &&
          !userTables.contains(routeFocused))
        routeFocused,
    ];
  }

  final peekFocusedSystem = !systemTablesExpanded &&
      routeFocused != null &&
      isSystemSqliteTable(routeFocused.sqliteName);
  final includeSystem = systemTablesExpanded || peekFocusedSystem;

  return [
    ...userTables,
    if (includeSystem) ...systemTables,
  ];
}
