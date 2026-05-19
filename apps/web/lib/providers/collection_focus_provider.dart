import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_web/auth/auth_route_provider.dart';
import 'package:zonai_web/auth/auth_routes.dart';

import 'sqlite_tables_provider.dart';

final collectionFocusProvider = NotifierProvider<CollectionFocusNotifier, SqliteCollectionRef?>(
  CollectionFocusNotifier.new,
);

class CollectionFocusNotifier extends Notifier<SqliteCollectionRef?> {
  @override
  SqliteCollectionRef? build() {
    ref.watch(authRouteProvider);
    final tables = ref.watch(sqliteTablesProvider);
    final sqliteName = AuthRoutes.collectionSqliteNameFromPath(ref.read(authRouteProvider));
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

  void setFocused(SqliteCollectionRef collection) {
    ref.read(authRouteProvider.notifier).navigateTo(
      AuthRoutes.forCollection(collection.sqliteName),
    );
  }

  void clear() {
    ref.read(authRouteProvider.notifier).navigateTo(AuthRoutes.home);
  }
}
