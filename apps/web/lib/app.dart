import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import 'auth/auth_provider.dart';
import 'components/home_screen.dart';
import 'components/sign_in_screen.dart';
import 'providers/sqlite_tables_provider.dart';

/// Root widget mounted into `<body>` by [runApp].
class App extends StatelessComponent {
  const App({super.key, required this.initialTables, this.tablesLoadError});

  final List<String> initialTables;
  final String? tablesLoadError;

  @override
  Component build(BuildContext context) {
    return div(classes: 'app-root', [AppShell(initialTables: initialTables, tablesLoadError: tablesLoadError)]);
  }

  @css
  static List<StyleRule> get styles => [css('.app-root').styles(minHeight: 100.vh, display: .flex)];
}

@client
class AppShell extends StatelessComponent {
  const AppShell({super.key, required this.initialTables, this.tablesLoadError});

  final List<String> initialTables;
  final String? tablesLoadError;

  @override
  Component build(BuildContext context) {
    return ProviderScope(
      overrides: [
        sqliteTablesProvider.overrideWithValue(SqliteTablesSnapshot(names: initialTables, loadError: tablesLoadError)),
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
