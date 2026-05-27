import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_web/auth/auth_route_provider.dart';
import 'package:zonai_web/auth/auth_routes.dart';

import 'sqlite_tables_provider.dart';

/// Table implied by the current URL (derived from route + SSR table list).
SqliteTableRef? resolveTableFocus(String path, SqliteTablesSnapshot tables) {
  final sqliteName = AuthRoutes.tableSqliteNameFromPath(path);
  if (sqliteName == null) {
    return null;
  }

  for (final table in tables.tables) {
    if (table.sqliteName == sqliteName) {
      return table;
    }
  }
  return null;
}

final tableFocusProvider = NotifierProvider<TableFocusNotifier, SqliteTableRef?>(
  TableFocusNotifier.new,
);

class TableFocusNotifier extends Notifier<SqliteTableRef?> {
  @override
  SqliteTableRef? build() {
    final path = ref.watch(authRouteProvider);
    final tables = ref.watch(sqliteTablesProvider);
    return resolveTableFocus(path, tables);
  }

  void setFocused(SqliteTableRef table) {
    ref.read(authRouteProvider.notifier).navigateTo(
      AuthRoutes.forTable(table.sqliteName),
    );
  }

  void clear() {
    ref.read(authRouteProvider.notifier).navigateTo(AuthRoutes.home);
  }
}
