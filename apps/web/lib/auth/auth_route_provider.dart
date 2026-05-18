import 'dart:async';

import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import 'auth_routes.dart';

final authRouteProvider = NotifierProvider<AuthRouteNotifier, String>(
  AuthRouteNotifier.new,
);

class AuthRouteNotifier extends Notifier<String> {
  AuthRouteNotifier({this.initialPath});

  final String? initialPath;

  StreamSubscription<web.PopStateEvent>? _popStateSubscription;

  @override
  String build() {
    if (!ref.binding.isClient) {
      return AuthRoutes.normalizePath(initialPath ?? AuthRoutes.signIn);
    }

    _listenToPopState();
    return AuthRoutes.normalizePath(_browserPath());
  }

  void navigateTo(String path) {
    final normalized = AuthRoutes.normalizePath(path);
    if (ref.binding.isClient) {
      web.window.history.pushState(null, '', normalized);
    }
    state = normalized;
  }

  void _listenToPopState() {
    if (_popStateSubscription != null) {
      return;
    }

    _popStateSubscription = web.window.onPopState.listen((_) {
      state = AuthRoutes.normalizePath(_browserPath());
    });

    ref.onDispose(() {
      _popStateSubscription?.cancel();
      _popStateSubscription = null;
    });
  }

  static String _browserPath() => web.window.location.pathname;
}
