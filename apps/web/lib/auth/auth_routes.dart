import 'package:zonai_schema/payloads.dart';

/// Sign-in URL paths for the web app.
abstract final class AuthRoutes {
  static const home = '/';
  static const signIn = '/sign-in';

  static String forType(AuthType type) => '$signIn/${type.name}';

  static bool isSignInPath(String path) {
    final normalized = normalizePath(path);
    return normalized == signIn || normalized.startsWith('$signIn/');
  }

  static bool isSignInRoot(String path) {
    final normalized = normalizePath(path);
    return normalized == home || normalized == signIn;
  }

  static AuthType? typeFromPath(String path) {
    final normalized = _normalizePath(path);
    if (!normalized.startsWith('$signIn/')) {
      return null;
    }

    final segment = normalized.substring('$signIn/'.length);
    if (segment.isEmpty || segment.contains('/')) {
      return null;
    }

    return AuthType.values
        .where((type) => type.name == segment)
        .firstOrNull;
  }

  static String normalizePath(String path) => _normalizePath(path);

  static String _normalizePath(String path) {
    if (path.isEmpty) {
      return home;
    }

    var normalized = path;
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
