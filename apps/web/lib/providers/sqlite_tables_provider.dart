import 'package:jaspr_riverpod/jaspr_riverpod.dart';

/// Result of reading [zonai.sqlite] table names on the server (SSR).
class SqliteTablesSnapshot {
  const SqliteTablesSnapshot({required this.names, this.loadError});

  final List<String> names;
  final String? loadError;
}

/// Must be overridden at the root [ProviderScope] (see [AppShell]).
final sqliteTablesProvider = Provider<SqliteTablesSnapshot>(
  (ref) => throw StateError('sqliteTablesProvider was not overridden'),
);
