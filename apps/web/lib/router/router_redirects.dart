import 'package:jaspr_router/jaspr_router.dart';

import '../auth/auth_routes.dart';

/// Shared [Router] redirects for the `/_` app mount.
abstract final class AppRouterRedirects {
  /// Rewrites mount-prefixed locations (e.g. `/_/tables/foo`) to app paths (`/tables/foo`).
  static String? normalizeMountPath(RouteState state) {
    final normalized = AuthRoutes.normalizePath(state.location);
    final rawPath = _rawPath(state.location);
    if (rawPath != normalized) {
      return normalized;
    }
    return null;
  }

  static String _rawPath(String location) {
    final uri = location.contains('://')
        ? Uri.parse(location)
        : Uri.parse('http://localhost$location');
    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }
}
