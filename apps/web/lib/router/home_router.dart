import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import '../auth/auth_routes.dart';
import '../components/home_screen.dart' deferred as home_screen;
import 'route_path_sync.dart';
import 'router_redirects.dart';

/// Router for the signed-in tables UI inside [HomeAppShell].
class HomeRouter extends StatelessComponent {
  const HomeRouter({super.key});

  @override
  Component build(BuildContext context) {
    return Router(
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
    if (AppRouterRedirects.normalizeMountPath(state) case final target?) {
      return target;
    }

    final path = AuthRoutes.normalizePath(state.location);
    if (AuthRoutes.isSignInPath(path) || AuthRoutes.isVerifyEmailCallbackPath(path)) {
      return AuthRoutes.home;
    }
    return null;
  }
}

final List<RouteBase> homeRoutes = [
  Route.lazy(
    path: '/tables/:sqliteName',
    name: 'table',
    builder: (_, _) => home_screen.HomeScreen(),
    load: home_screen.loadLibrary,
  ),
  Route.lazy(
    path: AuthRoutes.home,
    name: 'home',
    builder: (_, _) => home_screen.HomeScreen(),
    load: home_screen.loadLibrary,
  ),
];
