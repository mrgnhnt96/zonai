import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:zonai_schema/payloads.dart';

import 'components/auth_app_shell.dart';
import 'components/home_app_shell.dart';

/// Root widget mounted into `<body>` by [runApp].
class App extends StatelessComponent {
  const App({
    super.key,
    required this.appConfig,
    required this.initialSqliteNames,
    required this.initialDisplayNames,
    this.tablesLoadError,
    required this.initialSchemaShapes,
    required this.initialSignedIn,
    required this.initialPath,
    required this.initialAuthTypes,
  }) : assert(initialSqliteNames.length == initialDisplayNames.length, 'SQLite names and display labels must align');

  final AppConfig appConfig;
  final List<String> initialSqliteNames;
  final List<String> initialDisplayNames;
  final String? tablesLoadError;
  final Map<String, Map<String, Object?>> initialSchemaShapes;
  final bool initialSignedIn;
  final String initialPath;
  final List<AuthType> initialAuthTypes;

  @override
  Component build(BuildContext context) {
    return div(classes: 'app-root', [
      if (initialSignedIn)
        HomeAppShell(
          initialSqliteNames: initialSqliteNames,
          initialDisplayNames: initialDisplayNames,
          tablesLoadError: tablesLoadError,
          initialSchemaShapes: initialSchemaShapes,
          initialPath: initialPath,
          initialAppName: appConfig.appName,
        )
      else
        AuthAppShell(
          initialPath: initialPath,
          initialAppName: appConfig.appName,
          initialAuthTypeNames: [for (final type in initialAuthTypes) type.name],
        ),
    ]);
  }

  @css
  static List<StyleRule> get styles => [css('.app-root').styles(minHeight: 100.vh, display: .flex)];
}
