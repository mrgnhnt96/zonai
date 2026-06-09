import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import '../auth/auth_routes.dart';
import '../components/dashboard_screen.dart';
import '../components/home_screen.dart';
import 'route_path_sync.dart';
import 'router_error.dart';

/// Router for the signed-in tables UI inside [HomeAppShell].
class HomeRouter extends StatelessComponent {
  const HomeRouter({required this.initialPath, super.key});

  /// Normalized app path from SSR (see [HomeAppShell.initialPath]).
  final String initialPath;

  @override
  Component build(BuildContext context) {
    return Router(
      errorBuilder: routerErrorBuilder(initialPath),
      redirect: _redirect,
      routes: [
        ShellRoute(
          builder: (_, _, child) => RoutePathSync(child: child),
          routes: homeRoutes,
        ),
      ],
    );
  }

  static String? _redirect(BuildContext context, RouteState state) {
    if (AuthRoutes.routerRedirectToMountedLocation(state.location) case final mountedRedirect?) {
      return mountedRedirect;
    }

    final path = AuthRoutes.normalizePath(state.location);
    if (AuthRoutes.isSignInPath(path) || AuthRoutes.isVerifyEmailCallbackPath(path)) {
      return AuthRoutes.toUrlPath(AuthRoutes.home);
    }
    return null;
  }
}

final List<RouteBase> homeRoutes = [
  // More specific paths first so `/_` does not partially match table URLs during routing.
  Route(path: '${AuthRoutes.mountPath}/tables/:sqliteName', name: 'table', builder: (_, _) => const HomeScreen()),
  Route(path: '${AuthRoutes.mountPath}/tables', name: 'tables', builder: (_, _) => const HomeScreen()),
  Route(path: AuthRoutes.mountPath, name: 'dashboard', builder: (_, _) => const DashboardScreen()),
];
