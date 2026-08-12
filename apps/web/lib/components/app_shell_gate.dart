import 'package:jaspr/jaspr.dart';

import 'auth_app_shell.dart';
import 'home_app_shell.dart';

/// Picks the signed-in or auth client island for SSR.
///
/// Must stay a **server** component so [HomeAppShell] and [AuthAppShell] are not
/// nested inside another `@client` component (Jaspr allows only one client
/// anchor level from the server tree).
class AppShellGate extends StatelessComponent {
  const AppShellGate({
    super.key,
    required this.initialSignedIn,
    required this.initialPath,
    required this.initialAppName,
    required this.initialBaseUrl,
    required this.hasBrandLogo,
    required this.initialAuthTypeNames,
    required this.initialSqliteNames,
    required this.initialDisplayNames,
    this.tablesLoadError,
    required this.initialSchemaShapes,
    required this.initialCollectionActions,
    required this.initialPhotosConfig,
  }) : assert(initialSqliteNames.length == initialDisplayNames.length, 'SQLite names and display labels must align');

  final bool initialSignedIn;
  final String initialPath;
  final String initialAppName;
  final String initialBaseUrl;
  final bool hasBrandLogo;
  final List<String> initialAuthTypeNames;
  final List<String> initialSqliteNames;
  final List<String> initialDisplayNames;
  final String? tablesLoadError;
  final Map<String, Map<String, Object?>> initialSchemaShapes;
  final Map<String, Map<String, Object?>> initialCollectionActions;
  final Map<String, Object?> initialPhotosConfig;

  @override
  Component build(BuildContext context) {
    if (initialSignedIn) {
      return HomeAppShell(
        initialSqliteNames: initialSqliteNames,
        initialDisplayNames: initialDisplayNames,
        tablesLoadError: tablesLoadError,
        initialSchemaShapes: initialSchemaShapes,
        initialCollectionActions: initialCollectionActions,
        initialPath: initialPath,
        initialAppName: initialAppName,
        initialBaseUrl: initialBaseUrl,
        hasBrandLogo: hasBrandLogo,
        initialPhotosConfig: initialPhotosConfig,
      );
    }

    return AuthAppShell(
      initialPath: initialPath,
      initialAppName: initialAppName,
      initialBaseUrl: initialBaseUrl,
      hasBrandLogo: hasBrandLogo,
      initialAuthTypeNames: initialAuthTypeNames,
    );
  }
}
