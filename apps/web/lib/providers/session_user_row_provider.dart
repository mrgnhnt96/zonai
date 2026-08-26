import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_routes.dart';
import '../router/app_navigation.dart';
import '../utils/session_user_row_lookup.dart';
import '../utils/user_facing_error.dart';
import '../api/api_client.dart';
import 'app_base_url_provider.dart';
import 'foreign_key_rows_provider.dart';
import 'pending_row_detail_provider.dart';
import 'sqlite_tables_provider.dart';
import 'table_focus_provider.dart';
import 'table_row_detail_provider.dart';
import 'table_schema_provider.dart';
import 'toast_provider.dart';

/// The session `user_id` whose row is currently being looked up, or null.
///
/// Held so the control that started it can say it is working, and so a second
/// lookup is refused while one is in flight: the probe costs a request per
/// auth collection, and the panel it ends in can only show one row.
final sessionUserRowProvider = NotifierProvider<SessionUserRowNotifier, String?>(SessionUserRowNotifier.new);

class SessionUserRowNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Opens the row-detail panel on the collection row [userId] names.
  ///
  /// The collection is not known up front — see [sessionUserLookupCandidates]
  /// for why — so this probes them in order and stops at the first hit.
  Future<void> open(BuildContext context, String userId) async {
    if (state != null) return;
    state = userId;

    try {
      final schemas = ref.read(tableSchemasProvider);
      final candidates = sessionUserLookupCandidates(schemas: schemas, tables: ref.read(sqliteTablesProvider).tables);

      String? lastError;
      for (final candidate in candidates) {
        final ForeignKeyReferencedRow? found;
        try {
          found = await loadForeignKeyReferencedRow(
            server: ref.read(revaliServerProvider),
            imageBaseUrl: ref.read(appBaseUrlProvider),
            foreignKey: ForeignKeyShape(table: candidate.sqliteName, column: candidate.idColumn),
            parsedValue: userId,
            schema: schemas[candidate.sqliteName],
          );
        } on Object catch (error) {
          // One collection refusing to list — a rule the signed-in admin does
          // not satisfy — is not the end of the search: the row may well be in
          // the next one. The error is only reported if nothing matches.
          lastError = userFacingError(error);
          continue;
        }

        if (found == null) continue;
        _openFound(context, found);
        return;
      }

      ref.read(toastProvider.notifier).showError(lastError ?? 'No collection has a row with id "$userId".');
    } on Object catch (error) {
      // Nothing above is expected to throw — the per-candidate catch owns the
      // requests — but a click that silently did nothing would read as a dead
      // control rather than a bug.
      ref.read(toastProvider.notifier).showError(userFacingError(error));
    } finally {
      state = null;
    }
  }

  void _openFound(BuildContext context, ForeignKeyReferencedRow found) {
    // Already standing on that table: the route would not change, so no focus
    // change comes to consume a pending row. Open it outright instead.
    if (ref.read(tableFocusProvider)?.sqliteName == found.sqliteName) {
      ref
          .read(tableRowDetailProvider.notifier)
          .open(
            rowKey: found.rowKey,
            row: found.row,
            sqliteName: found.sqliteName,
            columns: found.columns,
            columnShapes: found.columnShapes,
          );
      return;
    }

    ref
        .read(pendingRowDetailProvider.notifier)
        .set(
          PendingRowDetail(
            sqliteName: found.sqliteName,
            rowKey: found.rowKey,
            row: found.row,
            columns: found.columns,
            columnShapes: found.columnShapes,
          ),
        );
    context.goApp(AuthRoutes.forTable(found.sqliteName));
  }
}
