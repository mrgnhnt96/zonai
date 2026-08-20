import 'package:jaspr/jaspr.dart';

import '../auth/auth_routes.dart';
import 'auth_app_shell.dart';
import 'home_app_shell.dart';

/// Picks the signed-in or auth client island for SSR.
///
/// Must stay a **server** component so [HomeAppShell] and [AuthAppShell] are not
/// nested inside another `@client` component (Jaspr allows only one client
/// anchor level from the server tree).
///
/// The session is not the only input: an
/// [AuthRoutes.isSignedInReachableAuthPath] request gets [AuthAppShell] even
/// when the cookie verifies, because those pages act on the account named in
/// the URL rather than the one holding the session. Routing them into
/// [HomeAppShell] is what sent a reset link to `/_` — that router has no route
/// for them and bounces every sign-in path home.
class AppShellGate extends StatelessComponent {
  const AppShellGate({
    super.key,
    required this.initialSignedIn,
    required this.initialPath,
    required this.initialAppName,
    required this.initialBaseUrl,
    required this.hasBrandLogo,
    required this.initialAuthTypeNames,
    required this.initialOAuthProviders,
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
  final List<Map<String, Object?>> initialOAuthProviders;
  final List<String> initialSqliteNames;
  final List<String> initialDisplayNames;
  final String? tablesLoadError;
  final Map<String, Map<String, Object?>> initialSchemaShapes;
  final Map<String, Map<String, Object?>> initialCollectionActions;
  final Map<String, Object?> initialPhotosConfig;

  /// Whether a request in this state gets [HomeAppShell] rather than
  /// [AuthAppShell].
  ///
  /// A named seam rather than an `if` inside [build], so the decision can be
  /// asserted without pumping two client islands and a router.
  static bool showsHomeShell({required bool initialSignedIn, required String initialPath}) {
    return initialSignedIn && !AuthRoutes.isSignedInReachableAuthPath(initialPath);
  }

  @override
  Component build(BuildContext context) {
    if (showsHomeShell(initialSignedIn: initialSignedIn, initialPath: initialPath)) {
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
      initialOAuthProviders: initialOAuthProviders,
    );
  }
}
