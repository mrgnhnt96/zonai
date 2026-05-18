import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import 'sqlite_tables_provider.dart';

final collectionFocusProvider = NotifierProvider<CollectionFocusNotifier, SqliteCollectionRef?>(
  CollectionFocusNotifier.new,
);

class CollectionFocusNotifier extends Notifier<SqliteCollectionRef?> {
  @override
  SqliteCollectionRef? build() => null;

  void setFocused(SqliteCollectionRef collection) => state = collection;

  void clear() => state = null;
}
