import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import '../auth/auth_routes.dart';

/// Hides the router error page while hydration resolves a path SSR already validated.
RouterComponentBuilder routerErrorBuilder(String initialPath) {
  return (context, state) {
    if (_isHydratingKnownPath(state.location, initialPath)) {
      return const Component.text('');
    }
    return div([Component.text('Page Not Found'), br(), Component.text(state.error?.toString() ?? 'page not found')]);
  };
}

bool _isHydratingKnownPath(String location, String initialPath) {
  return AuthRoutes.normalizePath(location) == AuthRoutes.normalizePath(initialPath);
}
