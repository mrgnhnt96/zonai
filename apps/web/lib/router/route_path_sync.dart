import 'dart:async';

import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_route_provider.dart';

/// Keeps [authRouteProvider] aligned with [RouteState] for auth guards and titles.
class RoutePathSync extends StatefulComponent {
  const RoutePathSync({required this.child, super.key});

  final Component child;

  @override
  State<RoutePathSync> createState() => _RoutePathSyncState();
}

class _RoutePathSyncState extends State<RoutePathSync> {
  String? _lastPath;

  @override
  Component build(BuildContext context) {
    // SSR seeds [authRouteProvider] from [initialPath]; sync only on the client.
    if (context.binding.isClient) {
      final path = appPathFromContext(context);
      if (_lastPath != path) {
        final previous = _lastPath;
        _lastPath = path;
        scheduleMicrotask(() {
          if (!mounted) return;
          context.read(authRouteProvider.notifier).notifyPathChanged(path, previous: previous);
        });
      }
    }

    return component.child;
  }
}
