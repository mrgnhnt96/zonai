import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../providers/app_name_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../utils/page_title.dart';

/// Keeps `<title>` in sync with auth state and the current route.
class PageTitleHead extends StatelessComponent {
  const PageTitleHead({super.key});

  @override
  Component build(BuildContext context) {
    final appName = context.watch(appNameProvider);
    final signedIn = context.watch(authProvider);
    final path = context.watch(authRouteProvider);
    String? tableDisplayName;
    if (signedIn) {
      final tables = context.watch(sqliteTablesProvider);
      tableDisplayName = PageTitle.tableDisplayNameForPath(
        path,
        sqliteNames: [for (final c in tables.tables) c.sqliteName],
        displayNames: [for (final c in tables.tables) c.displayName],
      );
    }

    return Document.head(
      title: PageTitle.resolve(
        appName: appName,
        signedIn: signedIn,
        path: path,
        tableDisplayName: tableDisplayName,
      ),
    );
  }
}
