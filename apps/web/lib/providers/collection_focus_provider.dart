import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_web/auth/auth_route_provider.dart';
import 'package:zonai_web/auth/auth_routes.dart';

import 'sqlite_tables_provider.dart';

/// Collection implied by the current URL (derived from route + SSR table list).
SqliteCollectionRef? resolveCollectionFocus(String path, SqliteTablesSnapshot tables) {
  final sqliteName = AuthRoutes.collectionSqliteNameFromPath(path);
  if (sqliteName == null) {
    return null;
  }

  for (final collection in tables.collections) {
    if (collection.sqliteName == sqliteName) {
      return collection;
    }
  }
  return null;
}

final collectionFocusProvider = NotifierProvider<CollectionFocusNotifier, SqliteCollectionRef?>(
  CollectionFocusNotifier.new,
);

class CollectionFocusNotifier extends Notifier<SqliteCollectionRef?> {
  @override
  SqliteCollectionRef? build() {
    final path = ref.watch(authRouteProvider);
    final tables = ref.watch(sqliteTablesProvider);
    return resolveCollectionFocus(path, tables);
  }

  void setFocused(SqliteCollectionRef collection) {
    ref.read(authRouteProvider.notifier).navigateTo(
      AuthRoutes.forCollection(collection.sqliteName),
    );
  }

  void clear() {
    ref.read(authRouteProvider.notifier).navigateTo(AuthRoutes.home);
  }
}
