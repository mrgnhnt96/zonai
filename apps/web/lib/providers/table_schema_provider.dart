import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import 'table_focus_provider.dart';

/// All collection schema shapes, hydrated from SSR.
final tableSchemasProvider = Provider<Map<String, TableSchemaShape>>(
  (ref) => throw StateError('tableSchemasProvider was not overridden'),
);

/// Schema shape for the focused table.
final tableSchemaProvider = Provider<TableSchemaShape?>((ref) {
  final focus = ref.watch(tableFocusProvider);
  if (focus == null) return null;
  return ref.watch(tableSchemasProvider)[focus.sqliteName];
});
