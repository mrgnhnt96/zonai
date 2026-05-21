import '../auth/auth_routes.dart';

/// Browser tab titles for app routes.
abstract final class PageTitle {
  PageTitle._();

  static String resolve({
    required String appName,
    required bool signedIn,
    required String path,
    String? collectionDisplayName,
  }) {
    if (AuthRoutes.isVerifyEmailCallbackPath(path)) {
      return '$appName — Verify email';
    }

    if (!signedIn) {
      if (AuthRoutes.isMagicLinkCallbackPath(path)) {
        return '$appName — Sign in';
      }
      if (AuthRoutes.isResetPasswordCallbackPath(path)) {
        return '$appName — Reset password';
      }
      if (AuthRoutes.isResetPasswordRequestPath(path)) {
        return '$appName — Reset password';
      }

      return switch (AuthRoutes.typeFromPath(path)) {
        .password => '$appName — Sign in',
        .otp => '$appName — Sign in with code',
        .magicLink => '$appName — Sign in with link',
        null => '$appName — Sign in',
      };
    }

    if (collectionDisplayName != null) {
      return '$collectionDisplayName — $appName';
    }

    return '$appName — Collections';
  }

  /// Resolves a collection label from [path] using parallel name lists from SSR.
  static String? collectionDisplayNameForPath(
    String path, {
    required List<String> sqliteNames,
    required List<String> displayNames,
  }) {
    final sqliteName = AuthRoutes.collectionSqliteNameFromPath(path);
    if (sqliteName == null) return null;

    for (var i = 0; i < sqliteNames.length; i++) {
      if (sqliteNames[i] == sqliteName) {
        return displayNames[i];
      }
    }
    return null;
  }
}
