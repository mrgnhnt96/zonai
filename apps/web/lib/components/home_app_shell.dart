import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../providers/sqlite_tables_provider.dart';
import 'app_shell_overrides.dart';
import 'page_title_head.dart';
import '../router/home_router.dart';

/// Client island for the signed-in tables UI (lazy-loaded separately from auth).
@client
class HomeAppShell extends StatelessComponent {
  const HomeAppShell({
    super.key,
    required this.initialSqliteNames,
    required this.initialDisplayNames,
    this.tablesLoadError,
    required this.initialSchemaShapes,
    required this.initialPath,
    required this.initialAppName,
  }) : assert(initialSqliteNames.length == initialDisplayNames.length, 'SQLite names and display labels must align');

  final List<String> initialSqliteNames;
  final List<String> initialDisplayNames;
  final String? tablesLoadError;
  final Map<String, Map<String, Object?>> initialSchemaShapes;
  final String initialPath;
  final String initialAppName;

  @override
  Component build(BuildContext context) {
    final tables = <SqliteTableRef>[
      for (var i = 0; i < initialSqliteNames.length; i++)
        SqliteTableRef(sqliteName: initialSqliteNames[i], displayName: initialDisplayNames[i]),
    ];
    final schemaShapes = {
      for (final MapEntry(:key, :value) in initialSchemaShapes.entries)
        key: TableSchemaShape.fromJson(Map<String, dynamic>.from(value)),
    };
    return ProviderScope(
      overrides: appShellOverrides(
        initialSignedIn: true,
        initialPath: initialPath,
        initialAppName: initialAppName,
        initialAuthTypes: const [],
        tables: SqliteTablesSnapshot(tables: tables, loadError: tablesLoadError),
        schemaShapes: schemaShapes,
      ),
      child: Component.fragment([const PageTitleHead(), const HomeRouter()]),
    );
  }
}
