import 'dart:async';
import 'dart:convert';

import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_riverpod/misc.dart' show Override;
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';
import 'package:zonai_web/utils/zonai_cookie.dart';

import 'sqlite_tables_provider.dart';
import 'session_user_provider.dart';
import 'table_focus_provider.dart';
import 'table_schema_provider.dart';

final _tableCollectionActionsSourceProvider =
    NotifierProvider<TableCollectionActionsNotifier, Map<String, TableCollectionActions>>(
      TableCollectionActionsNotifier.new,
    );

/// Hydrated from SSR and refreshed on the client after sign-in.
final tableCollectionActionsProvider = Provider<Map<String, TableCollectionActions>>(
  (ref) => ref.watch(_tableCollectionActionsSourceProvider),
);

class TableCollectionActionsNotifier extends Notifier<Map<String, TableCollectionActions>> {
  TableCollectionActionsNotifier({this._initial = const {}});

  final Map<String, TableCollectionActions> _initial;

  @override
  Map<String, TableCollectionActions> build() {
    if (ref.binding.isClient) {
      scheduleMicrotask(refresh);
    }
    return _initial;
  }

  Future<void> refresh() async {
    final token = ZonaiCookie.authToken.read();
    if (token == null || token.isEmpty) {
      state = const {};
      return;
    }

    try {
      final response = await revaliServer.client.request(
        method: 'GET',
        path: '/db/collection-actions',
        headers: {'authorization': 'Bearer $token'},
      );
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return;

      state = {
        for (final MapEntry(:key, :value) in decoded.entries)
          if (value is Map) key as String: TableCollectionActions.fromJson(Map<String, dynamic>.from(value)),
      };
    } on Object {
      // Keep SSR-hydrated or fallback permissions when refresh fails.
    }
  }
}

/// Override for [ProviderScope] during SSR hydration.
Override tableCollectionActionsOverride(Map<String, TableCollectionActions> initial) {
  return _tableCollectionActionsSourceProvider.overrideWith(() => TableCollectionActionsNotifier(initial: initial));
}

/// Actions allowed on the focused collection.
final focusedCollectionActionsProvider = Provider<TableCollectionActions?>((ref) {
  final focus = ref.watch(tableFocusProvider);
  if (focus == null) return null;
  return ref.watch(tableCollectionActionsProvider)[focus.sqliteName];
});

/// A collection resolved from sidebar focus, schema shape, and allowed actions.
final class ResolvedCollection {
  const ResolvedCollection({required this.table, required this.schema, required this.actions});

  final SqliteTableRef table;
  final TableSchemaShape? schema;
  final TableCollectionActions actions;
}

/// Joins table focus, schema metadata, and rule-derived actions.
ResolvedCollection? resolveCollection({
  required SqliteTableRef? focus,
  required Map<String, TableSchemaShape> schemas,
  required Map<String, TableCollectionActions> actions,
}) {
  if (focus == null) return null;

  return ResolvedCollection(
    table: focus,
    schema: schemas[focus.sqliteName],
    actions: actions[focus.sqliteName] ?? TableCollectionActions.denied(focus.sqliteName),
  );
}

final resolvedCollectionProvider = Provider<ResolvedCollection?>((ref) {
  return resolveCollection(
    focus: ref.watch(tableFocusProvider),
    schemas: ref.watch(tableSchemasProvider),
    actions: ref.watch(tableCollectionActionsProvider),
  );
});

/// Shared inputs for row mutation permission checks in the admin UI.
({Map<String, TableCollectionActions> allActions, bool sessionCanEdit}) tableMutationAccess(Ref ref) {
  return (
    allActions: ref.watch(tableCollectionActionsProvider),
    sessionCanEdit: ref.watch(sessionUserProvider)?.canEdit == true,
  );
}
