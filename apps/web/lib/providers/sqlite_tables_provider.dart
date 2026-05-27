import 'package:jaspr_riverpod/jaspr_riverpod.dart';

/// One SQLite-backed table: UI label may differ from the real table name.
final class SqliteTableRef {
  const SqliteTableRef({required this.sqliteName, required this.displayName});

  final String sqliteName;
  final String displayName;

  @override
  bool operator ==(Object other) => other is SqliteTableRef && other.sqliteName == sqliteName;

  @override
  int get hashCode => sqliteName.hashCode;
}

/// Result of reading [zonai.sqlite] table names on the server (SSR).
class SqliteTablesSnapshot {
  const SqliteTablesSnapshot({required this.tables, this.loadError});

  final List<SqliteTableRef> tables;
  final String? loadError;
}

/// Must be overridden at the root [ProviderScope] (see [AppShell]).
final sqliteTablesProvider = Provider<SqliteTablesSnapshot>(
  (ref) => throw StateError('sqliteTablesProvider was not overridden'),
);
