import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import 'components/app_shell_gate.dart';
import 'providers/photos_config_provider.dart';
import 'utils/page_title.dart';

/// Root widget mounted into `<body>` by [runApp].
class App extends StatelessComponent {
  const App({
    super.key,
    required this.appConfig,
    required this.hasBrandLogo,
    required this.initialSqliteNames,
    required this.initialDisplayNames,
    this.tablesLoadError,
    required this.initialSchemaShapes,
    required this.initialCollectionActions,
    required this.initialSignedIn,
    required this.initialPath,
    required this.initialAuthTypes,
    required this.initialOAuthProviders,
  }) : assert(initialSqliteNames.length == initialDisplayNames.length, 'SQLite names and display labels must align');

  final AppConfig appConfig;
  final bool hasBrandLogo;
  final List<String> initialSqliteNames;
  final List<String> initialDisplayNames;
  final String? tablesLoadError;
  final Map<String, Map<String, Object?>> initialSchemaShapes;
  final Map<String, Map<String, Object?>> initialCollectionActions;
  final bool initialSignedIn;
  final String initialPath;
  final List<AuthType> initialAuthTypes;
  final List<OAuthProviderPublic> initialOAuthProviders;

  @override
  Component build(BuildContext context) {
    final tableDisplayName = initialSignedIn
        ? PageTitle.tableDisplayNameForPath(
            initialPath,
            sqliteNames: initialSqliteNames,
            displayNames: initialDisplayNames,
          )
        : null;
    final title = PageTitle.resolve(
      appName: appConfig.appName,
      signedIn: initialSignedIn,
      path: initialPath,
      tableDisplayName: tableDisplayName,
    );

    return div(classes: 'app-root', [
      Document.head(
        title: title,
        meta: {
          'viewport': 'width=device-width, initial-scale=1',
          'description': PageTitle.description(
            appName: appConfig.appName,
            signedIn: initialSignedIn,
            path: initialPath,
            tableDisplayName: tableDisplayName,
          ),
          'og:title': title,
        },
      ),
      AppShellGate(
        initialSignedIn: initialSignedIn,
        initialPath: initialPath,
        initialAppName: appConfig.appName,
        initialBaseUrl: appConfig.baseUrl,
        hasBrandLogo: hasBrandLogo,
        initialAuthTypeNames: [for (final type in initialAuthTypes) type.name],
        initialOAuthProviders: [for (final provider in initialOAuthProviders) provider.toJson()],
        initialSqliteNames: initialSqliteNames,
        initialDisplayNames: initialDisplayNames,
        tablesLoadError: tablesLoadError,
        initialSchemaShapes: initialSchemaShapes,
        initialCollectionActions: initialCollectionActions,
        initialPhotosConfig: photosConfigToJson(appConfig.photos),
      ),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css(
      '.app-root',
    ).styles(height: 100.vh, display: .flex, flexDirection: FlexDirection.column, overflow: Overflow.hidden),
    css('.app-root > .home-app-shell').styles(flex: Flex(grow: 1, shrink: 1), minHeight: .zero),
  ];
}
