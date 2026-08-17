import 'package:zonai/deps.dart';
import 'package:zonai_schema/src/payloads/maintenance_actions.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/where.dart';

/// The Maintenance screen's destructive verbs.
///
/// Every method here wraps a verb that already exists on `ZonaiDb`; what this
/// class adds is the admin gate and the wire shape. Kept apart from
/// `DashboardHandler` deliberately — the dashboard is read-only by contract,
/// and these are not.
///
/// The gate is the same shape as `DashboardHandler.metrics`: parse the bearer
/// token, refuse anything that is not an admin, and refuse *before* doing any
/// work. Refusing first matters more here than it does for a read: these verbs
/// rewrite database files and delete rows, so a gate that ran after the work
/// would be no gate at all.
///
/// It is also the outer of two locks rather than the only one. `purge` checks
/// admin itself, host-side, because its request can arrive over IPC from a
/// worker process. Duplication here is intentional: this lock exists to stop
/// the work from starting, the engine's to stop it from happening.
class MaintenanceHandler {
  const MaintenanceHandler();

  /// Deletes log rows, optionally only those older than
  /// [PurgeLogsBody.olderThanDays] days.
  Future<MaintenanceRowsResult> purgeLogs(
    String? authorization, {
    required PurgeLogsBody body,
  }) async {
    await _requireAdmin(authorization, operation: 'purge_logs');

    final days = body.olderThanDays;
    if (days != null && days < 0) {
      throw ArgumentError.value(
        days,
        'older_than_days',
        'must not be negative',
      );
    }

    // `null` means every row; a cutoff means only what predates it. Computed
    // here rather than sent as a timestamp so the boundary is the server's
    // clock, not a browser's -- a client whose clock is a day fast would
    // otherwise delete a day more than the operator asked for.
    final before = days == null
        ? null
        : DateTime.now().subtract(Duration(days: days));

    final rows = await zonaiDB.clearLogs(before: before);
    return MaintenanceRowsResult(rowsAffected: rows);
  }

  /// Empties one of the framework's own tables.
  Future<MaintenanceRowsResult> purgeTable(
    String? authorization, {
    required PurgeTableBody body,
  }) async {
    final jwt = await _requireAdmin(authorization, operation: 'purge');

    // Checked here as well as in the engine. The engine's check is the one
    // that is load-bearing (it also covers the IPC path), but refusing an
    // unlisted table before opening the database keeps `_photos` from ever
    // reaching a code path that could delete its rows -- see
    // [kPurgeableTableNames] for why that particular table matters.
    if (!kPurgeableTableNames.contains(body.table)) {
      throw TableAccessDeniedException(table: body.table, operation: 'purge');
    }

    // Every internal table carries an `id` primary key, so "id is not null"
    // is a match-all that the operations layer will accept -- unlike `rowid`,
    // which is not in any generated schema. A purge with no predicate at all
    // is not expressible through `purge`, and giving the endpoint an operator
    // supplied `Where` would hand a browser arbitrary DELETE predicates
    // against framework tables for no gain.
    final rows = await zonaiDB.purge(
      table: body.table,
      where: const NotNull('id'),
      jwt: jwt,
    );

    return MaintenanceRowsResult(rowsAffected: rows);
  }

  /// Deletes photo rows nothing references, and the files behind them.
  ///
  /// The one cleanup that is not a purge: photo rows own a file each, deleted
  /// through a per-row path a bulk `DELETE` has no hook for, which is exactly
  /// why `_photos` is excluded from [purgeTable].
  Future<PhotoCleanupResult> cleanupPhotos(String? authorization) async {
    await _requireAdmin(authorization, operation: 'cleanup_photos');

    final deleted = await zonaiDB.cleanupUnreferencedPhotos();
    return PhotoCleanupResult(deletedCount: deleted);
  }

  /// Rewrites the log database when enough of it is dead space.
  ///
  /// Every field of the engine's result is passed through, [skipped] included
  /// and unmodified. Collapsing it to a boolean would erase the distinction
  /// the field exists for: a full volume fails the headroom check and reclaims
  /// nothing, which without the reason reads exactly like having had nothing
  /// to reclaim.
  Future<LogSpaceReclamationResult> reclaimLogSpace(
    String? authorization,
  ) async {
    await _requireAdmin(authorization, operation: 'reclaim_log_space');

    final result = await zonaiDB.reclaimLogSpace();
    return LogSpaceReclamationResult(
      reclaimableBytes: result.reclaimableBytes,
      reclaimedBytes: result.reclaimedBytes,
      vacuumed: result.vacuumed,
      skipped: result.skipped,
    );
  }

  /// Parses the bearer token and refuses anything that is not an admin.
  ///
  /// Returns the [Jwt] rather than a bool so callers that need an admin
  /// identity downstream (`purge` does) cannot end up re-parsing it, or worse,
  /// passing a different one than the gate approved.
  Future<Jwt> _requireAdmin(
    String? authorization, {
    required String operation,
  }) async {
    final jwt = await zonaiDB.parseJwt(
      _parseBearerAuthorization(authorization),
    );

    // `parseJwt` answers null for a token it cannot verify, which has to read
    // as "not an admin" rather than falling through.
    if (jwt == null || jwt.admin.isAdmin != true) {
      throw TableAccessDeniedException(
        table: '_maintenance',
        operation: operation,
      );
    }

    return jwt;
  }

  String? _parseBearerAuthorization(String? authorizationHeader) {
    if (authorizationHeader == null) {
      return null;
    }

    final trimmed = authorizationHeader.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    const prefix = 'Bearer ';
    if (trimmed.length >= prefix.length &&
        trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      return trimmed.substring(prefix.length).trim();
    }

    return null;
  }
}
