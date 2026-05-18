import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import 'auth/auth_provider.dart';
import 'components/home_screen.dart';
import 'components/sign_in_screen.dart';
import 'providers/sqlite_tables_provider.dart';

/// Root widget mounted into `<body>` by [runApp].
class App extends StatelessComponent {
  const App({
    super.key,
    required this.initialSqliteNames,
    required this.initialDisplayNames,
    this.tablesLoadError,
    required this.initialSignedIn,
  }) : assert(
          initialSqliteNames.length == initialDisplayNames.length,
          'SQLite names and display labels must align',
        );

  final List<String> initialSqliteNames;
  final List<String> initialDisplayNames;
  final String? tablesLoadError;
  final bool initialSignedIn;

  @override
  Component build(BuildContext context) {
    return div(classes: 'app-root', [
      AppShell(
        initialSqliteNames: initialSqliteNames,
        initialDisplayNames: initialDisplayNames,
        tablesLoadError: tablesLoadError,
        initialSignedIn: initialSignedIn,
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
  }) : assert(
          initialSqliteNames.length == initialDisplayNames.length,
          'SQLite names and display labels must align',
        );

  final List<String> initialSqliteNames;
  final List<String> initialDisplayNames;
  final String? tablesLoadError;
  final bool initialSignedIn;

  @override
  Component build(BuildContext context) {
    final collections = <SqliteCollectionRef>[
      for (var i = 0; i < initialSqliteNames.length; i++)
        SqliteCollectionRef(sqliteName: initialSqliteNames[i], displayName: initialDisplayNames[i]),
    ];
    return ProviderScope(
      overrides: [
        sqliteTablesProvider.overrideWithValue(SqliteTablesSnapshot(collections: collections, loadError: tablesLoadError)),
        authProvider.overrideWith(() => AuthNotifier(initialSignedIn: initialSignedIn)),
      ],
      child: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessComponent {
  const _AuthGate();

  @override
  Component build(BuildContext context) {
    final signedIn = context.watch(authProvider);
    if (signedIn) {
      return const HomeScreen();
    }
    return const SignInScreen();
  }
}
