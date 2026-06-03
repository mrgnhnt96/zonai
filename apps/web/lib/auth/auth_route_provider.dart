import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import 'auth_routes.dart';

export '../router/app_navigation.dart' show AppNavigation, appPathFromContext;

final authRouteProvider = NotifierProvider<AuthRouteNotifier, String>(
  AuthRouteNotifier.new,
);

/// Tracks the normalized app path for guards, titles, and table focus.
///
/// Updated by [RoutePathSync] from [jaspr_router] [RouteState].
class AuthRouteNotifier extends Notifier<String> {
  AuthRouteNotifier({this.initialPath});

  final String? initialPath;

  String? _previous;

  @override
  String build() => AuthRoutes.normalizePath(initialPath ?? AuthRoutes.signIn);

  /// Called when the active [RouteState] location changes.
  void notifyPathChanged(String path, {String? previous}) {
    final normalized = AuthRoutes.normalizePath(path);
    if (state == normalized) {
      return;
    }
    _previous = previous ?? _previous ?? state;
    state = normalized;
  }

  String? get previousPath => _previous;
}
