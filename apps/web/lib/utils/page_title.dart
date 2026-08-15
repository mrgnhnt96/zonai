import '../auth/auth_routes.dart';

/// Browser tab titles for app routes.
abstract final class PageTitle {
  PageTitle._();

  static String resolve({
    required String appName,
    required bool signedIn,
    required String path,
    String? tableDisplayName,
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
        .oauth => '$appName — Sign in',
        null => '$appName — Sign in',
      };
    }

    if (tableDisplayName != null) {
      return '$tableDisplayName — $appName';
    }

    return '$appName — Tables';
  }

  static String description({
    required String appName,
    required bool signedIn,
    required String path,
    String? tableDisplayName,
  }) {
    if (AuthRoutes.isVerifyEmailCallbackPath(path)) {
      return 'Verify your email address for $appName.';
    }

    if (!signedIn) {
      if (AuthRoutes.isMagicLinkCallbackPath(path)) {
        return 'Complete sign-in to $appName.';
      }
      if (AuthRoutes.isResetPasswordCallbackPath(path)) {
        return 'Choose a new password for your $appName account.';
      }
      if (AuthRoutes.isResetPasswordRequestPath(path)) {
        return 'Request a password reset link for $appName.';
      }

      return switch (AuthRoutes.typeFromPath(path)) {
        .password => 'Sign in to $appName with your email and password.',
        .otp => 'Sign in to $appName with a one-time code.',
        .magicLink => 'Sign in to $appName with a secure email link.',
        .oauth => 'Sign in to $appName.',
        null => 'Sign in to $appName.',
      };
    }

    if (tableDisplayName != null) {
      return 'View rows in $tableDisplayName — $appName.';
    }

    return 'Browse and manage tables in $appName.';
  }

  /// Resolves a table label from [path] using parallel name lists from SSR.
  static String? tableDisplayNameForPath(
    String path, {
    required List<String> sqliteNames,
    required List<String> displayNames,
  }) {
    final sqliteName = AuthRoutes.tableSqliteNameFromPath(path);
    if (sqliteName == null) return null;

    for (var i = 0; i < sqliteNames.length; i++) {
      if (sqliteNames[i] == sqliteName) {
        return displayNames[i];
      }
    }
    return null;
  }
}
