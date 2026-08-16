import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import '../auth/auth_routes.dart';
import '../components/admins_screen.dart';
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
    // An invite link opened in a browser that already holds a dashboard
    // session. That session is an admin one (the dashboard has no other kind),
    // so whoever is at the keyboard already has what the invite offers, and
    // the acceptance screen has nothing to tell them. Home, rather than this
    // router's "no such route" error — the link is not broken, it is spent on
    // this browser. Accepting as the invited identity means signing out first.
    if (AuthRoutes.isAdminInviteAcceptPath(path)) {
      return AuthRoutes.toUrlPath(AuthRoutes.home);
    }
    return null;
  }
}

final List<RouteBase> homeRoutes = [
  // More specific paths first so `/_` does not partially match table URLs during routing.
  Route(path: '${AuthRoutes.mountPath}/tables/:sqliteName', name: 'table', builder: (_, _) => const HomeScreen()),
  Route(path: '${AuthRoutes.mountPath}/tables', name: 'tables', builder: (_, _) => const HomeScreen()),
  Route(path: '${AuthRoutes.mountPath}${AuthRoutes.admins}', name: 'admins', builder: (_, _) => const AdminsScreen()),
  Route(path: AuthRoutes.mountPath, name: 'dashboard', builder: (_, _) => const DashboardScreen()),
];
