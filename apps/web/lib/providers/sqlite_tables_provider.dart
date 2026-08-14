import 'package:jaspr_riverpod/jaspr_riverpod.dart';

/// One table in the sidebar: a real SQLite-backed table, or a read-only view.
///
/// UI label may differ from the real table name. [isView] tables have no
/// `sqlite_master` row — they're sourced from schema shapes, not the SQLite
/// file, and never support create/update/delete.
final class SqliteTableRef {
  const SqliteTableRef({required this.sqliteName, required this.displayName, this.isView = false});

  final String sqliteName;
  final String displayName;
  final bool isView;

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
