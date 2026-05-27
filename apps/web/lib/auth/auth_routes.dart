import 'package:zonai_schema/payloads.dart';

/// URL paths for the web app.
abstract final class AuthRoutes {
  static const home = '/';
  static const signIn = '/sign-in';
  static const tables = '/tables';
  static const magicLinkCallback = '/auth/magic-link';
  static const resetPasswordCallback = '/auth/reset-password';
  static const resetPasswordRequest = '/auth/reset-password/request';
  static const verifyEmailCallback = '/auth/verify-email';

  /// Base path for the web app and Jaspr asset URL stripping.
  static const mountPath = '/_';

  static String forType(AuthType type) => '$signIn/${type.name}';

  static String forTable(String sqliteName) => '$tables/${Uri.encodeComponent(sqliteName)}';

  static String? tableSqliteNameFromPath(String path) {
    final normalized = normalizePath(path);
    final prefix = '$tables/';
    if (!normalized.startsWith(prefix)) {
      return null;
    }

    final segment = normalized.substring(prefix.length);
    if (segment.isEmpty || segment.contains('/')) {
      return null;
    }

    return Uri.decodeComponent(segment);
  }

  static bool isSignInPath(String path) {
    final normalized = normalizePath(path);
    return normalized == signIn ||
        normalized.startsWith('$signIn/') ||
        normalized == magicLinkCallback ||
        normalized == resetPasswordCallback ||
        normalized == resetPasswordRequest ||
        normalized == verifyEmailCallback;
  }

  static bool isVerifyEmailCallbackPath(String path) {
    return normalizePath(path) == verifyEmailCallback;
  }

  static bool isPublicAuthPath(String path) {
    return isSignInPath(path) || isVerifyEmailCallbackPath(path);
  }

  static bool isMagicLinkCallbackPath(String path) {
    return normalizePath(path) == magicLinkCallback;
  }

  static bool isResetPasswordCallbackPath(String path) {
    return normalizePath(path) == resetPasswordCallback;
  }

  static bool isResetPasswordRequestPath(String path) {
    return normalizePath(path) == resetPasswordRequest;
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

  static String fromUrlPath(String url) => normalizePath(url);

  /// Maps an app route (e.g. `/sign-in`) to its URL under [mountPath].
  static String toUrlPath(String path) {
    final normalized = normalizePath(path);
    if (mountPath == '/' || mountPath.isEmpty) {
      return normalized;
    }
    if (normalized == home) {
      return mountPath;
    }
    return '$mountPath$normalized';
  }

  static String _normalizePath(String path) {
    if (path.isEmpty) {
      return home;
    }

    final uri = path.contains('://') ? Uri.parse(path) : Uri.parse('http://localhost$path');
    var normalized = uri.path;
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    if (mountPath != '/' && mountPath.isNotEmpty) {
      if (normalized == mountPath) {
        return home;
      }
      final prefix = '$mountPath/';
      if (normalized.startsWith(prefix)) {
        normalized = normalized.substring(mountPath.length);
      }
    }

    return normalized;
  }
}
