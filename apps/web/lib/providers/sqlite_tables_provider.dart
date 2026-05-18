import 'package:jaspr_riverpod/jaspr_riverpod.dart';

/// One SQLite-backed collection/table: UI label may differ from the real table name.
final class SqliteCollectionRef {
  const SqliteCollectionRef({required this.sqliteName, required this.displayName});

  final String sqliteName;
  final String displayName;

  @override
  bool operator ==(Object other) => other is SqliteCollectionRef && other.sqliteName == sqliteName;

  @override
  int get hashCode => sqliteName.hashCode;
}

/// Result of reading [zonai.sqlite] table names on the server (SSR).
class SqliteTablesSnapshot {
  const SqliteTablesSnapshot({required this.collections, this.loadError});

  final List<SqliteCollectionRef> collections;
  final String? loadError;
}

/// Must be overridden at the root [ProviderScope] (see [AppShell]).
final sqliteTablesProvider = Provider<SqliteTablesSnapshot>(
  (ref) => throw StateError('sqliteTablesProvider was not overridden'),
);
