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
    if (!signedIn) {
      return switch (AuthRoutes.typeFromPath(path)) {
        .password => '$appName — Sign in',
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
