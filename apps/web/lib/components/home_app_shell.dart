import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../providers/photos_config_provider.dart';
import '../providers/sqlite_tables_provider.dart';
import '../utils/web_photos_schema.dart';
import 'app_shell_overrides.dart';
import 'app_tooltip_overlay.dart';
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
    required this.initialCollectionActions,
    required this.initialPath,
    required this.initialAppName,
    required this.initialBaseUrl,
    required this.hasBrandLogo,
    required this.initialPhotosConfig,
  }) : assert(initialSqliteNames.length == initialDisplayNames.length, 'SQLite names and display labels must align');

  final List<String> initialSqliteNames;
  final List<String> initialDisplayNames;
  final String? tablesLoadError;
  final Map<String, Map<String, Object?>> initialSchemaShapes;
  final Map<String, Map<String, Object?>> initialCollectionActions;
  final String initialPath;
  final String initialAppName;
  final String initialBaseUrl;
  final bool hasBrandLogo;
  final Map<String, Object?> initialPhotosConfig;

  @override
  Component build(BuildContext context) {
    final schemaShapes = augmentWebSchemaShapes({
      for (final MapEntry(:key, :value) in initialSchemaShapes.entries)
        key: TableSchemaShape.fromJson(Map<String, dynamic>.from(value)),
    });
    final tables = <SqliteTableRef>[
      for (var i = 0; i < initialSqliteNames.length; i++)
        SqliteTableRef(sqliteName: initialSqliteNames[i], displayName: initialDisplayNames[i]),
      // Views have no `sqlite_master` row, so they're never in the SQLite
      // name list above — they're only visible through their schema shape.
      for (final MapEntry(key: name, value: shape) in schemaShapes.entries)
        if (shape.isView) SqliteTableRef(sqliteName: name, displayName: name, isView: true),
    ];
    final collectionActions = {
      for (final MapEntry(:key, :value) in initialCollectionActions.entries)
        key: TableCollectionActions.fromJson(Map<String, dynamic>.from(value)),
    };
    return div(classes: 'home-app-shell', [
      ProviderScope(
        overrides: appShellOverrides(
          initialSignedIn: true,
          initialPath: initialPath,
          initialAppName: initialAppName,
          initialBaseUrl: initialBaseUrl,
          hasBrandLogo: hasBrandLogo,
          initialPhotosConfig: photosConfigFromJson(Map<String, dynamic>.from(initialPhotosConfig)),
          initialAuthTypes: const [],
          tables: SqliteTablesSnapshot(tables: tables, loadError: tablesLoadError),
          schemaShapes: schemaShapes,
          collectionActions: collectionActions,
        ),
        child: Component.fragment([
          const PageTitleHead(),
          div(classes: 'home-app-shell-body', [HomeRouter(initialPath: initialPath)]),
          const AppTooltipOverlay(),
        ]),
      ),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    ...AppTooltipOverlay.styles,
    css('.home-app-shell').styles(
      flex: Flex(grow: 1, shrink: 1),
      display: .flex,
      flexDirection: FlexDirection.column,
      minHeight: .zero,
      overflow: Overflow.hidden,
      width: 100.percent,
    ),
    css('.home-app-shell-body').styles(
      flex: Flex(grow: 1, shrink: 1),
      display: .flex,
      flexDirection: FlexDirection.column,
      minHeight: .zero,
      overflow: Overflow.hidden,
    ),
  ];
}
