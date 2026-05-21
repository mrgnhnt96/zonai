import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import 'auth/auth_provider.dart';
import 'auth/auth_route_provider.dart';
import 'auth/supported_auth_types_provider.dart';
import 'components/home_screen.dart';
import 'components/login_flow.dart';
import 'components/page_title_head.dart';
import 'providers/app_name_provider.dart';
import 'providers/sqlite_tables_provider.dart';

/// Root widget mounted into `<body>` by [runApp].
class App extends StatelessComponent {
  const App({
    super.key,
    required this.appConfig,
    required this.initialSqliteNames,
    required this.initialDisplayNames,
    this.tablesLoadError,
    required this.initialSignedIn,
    required this.initialPath,
    required this.initialAuthTypes,
  }) : assert(initialSqliteNames.length == initialDisplayNames.length, 'SQLite names and display labels must align');

  final AppConfig appConfig;
  final List<String> initialSqliteNames;
  final List<String> initialDisplayNames;
  final String? tablesLoadError;
  final bool initialSignedIn;
  final String initialPath;
  final List<AuthType> initialAuthTypes;

  @override
  Component build(BuildContext context) {
    return div(classes: 'app-root', [
      AppShell(
        initialSqliteNames: initialSqliteNames,
        initialDisplayNames: initialDisplayNames,
        tablesLoadError: tablesLoadError,
        initialSignedIn: initialSignedIn,
        initialPath: initialPath,
        initialAppName: appConfig.appName,
        initialAuthTypeNames: [for (final type in initialAuthTypes) type.name],
      ),
    ]);
  }

  @css
  static List<StyleRule> get styles => [css('.app-root').styles(minHeight: 100.vh, display: .flex)];
}

@client
class AppShell extends StatelessComponent {
  const AppShell({
    super.key,
    required this.initialSqliteNames,
    required this.initialDisplayNames,
    this.tablesLoadError,
    required this.initialSignedIn,
    required this.initialPath,
    required this.initialAppName,
    required this.initialAuthTypeNames,
  }) : assert(initialSqliteNames.length == initialDisplayNames.length, 'SQLite names and display labels must align');

  final List<String> initialSqliteNames;
  final List<String> initialDisplayNames;
  final String? tablesLoadError;
  final bool initialSignedIn;
  final String initialPath;
  final String initialAppName;
  final List<String> initialAuthTypeNames;

  @override
  Component build(BuildContext context) {
    final collections = <SqliteCollectionRef>[
      for (var i = 0; i < initialSqliteNames.length; i++)
        SqliteCollectionRef(sqliteName: initialSqliteNames[i], displayName: initialDisplayNames[i]),
    ];
    final initialAuthTypes = [for (final name in initialAuthTypeNames) AuthType.values.byName(name)];
    return ProviderScope(
      overrides: [
        sqliteTablesProvider.overrideWithValue(
          SqliteTablesSnapshot(collections: collections, loadError: tablesLoadError),
        ),
        authProvider.overrideWith(() => AuthNotifier(initialSignedIn: initialSignedIn)),
        authRouteProvider.overrideWith(() => AuthRouteNotifier(initialPath: initialPath)),
        supportedAuthTypesProvider.overrideWithValue(initialAuthTypes),
        appNameProvider.overrideWithValue(initialAppName),
      ],
      child: Component.fragment([const PageTitleHead(), const _AuthGate()]),
    );
  }
}

class _AuthGate extends StatefulComponent {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  Component build(BuildContext context) {
    final signedIn = context.watch(authProvider);
    if (signedIn) {
      return const HomeScreen();
    }
    return const LoginFlow();
  }
}
