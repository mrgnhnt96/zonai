import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import '../auth/auth_routes.dart';

/// Normalized app path (without [AuthRoutes.mountPath]) for the active route.
String appPathFromContext(BuildContext context) {
  final routeState = RouteState.maybeOf(context);
  if (routeState != null) {
    return AuthRoutes.normalizePath(routeState.location);
  }
  return AuthRoutes.normalizePath(context.url);
}

/// Client-side navigation under [AuthRoutes.mountPath].
extension AppNavigation on BuildContext {
  String get appPath => appPathFromContext(this);

  Future<void> goApp(String path, {bool replace = false}) {
    final mounted = AuthRoutes.toUrlPath(AuthRoutes.normalizePath(path));
    final router = Router.of(this);
    if (replace) {
      return router.replace(mounted);
    }
    return router.push(mounted);
  }
}
