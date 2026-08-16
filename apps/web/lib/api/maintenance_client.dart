import 'package:zonai_client/server.dart';
import 'package:zonai_schema/payloads.dart';

/// Storage usage for the maintenance screen.
///
/// Its own call rather than a field on the dashboard's metrics: collecting it
/// shells out to `df`, walks the photos directory and makes two pragma round
/// trips per database file, and the dashboard polls on a timer.
Future<StorageMetrics> fetchStorageMetrics({required Server server}) {
  return server.dashboard.storage();
}

/// Deletes log rows older than [olderThanDays], or every row when it is null.
///
/// The cutoff travels as a day count rather than a timestamp so the boundary
/// is computed against the server's clock. A browser running a day fast would
/// otherwise delete a day more than the operator asked for.
Future<MaintenanceRowsResult> purgeLogs({required Server server, required int? olderThanDays}) {
  return server.maintenance.purgeLogs(body: PurgeLogsBody(olderThanDays: olderThanDays));
}

/// Empties one of the framework's own tables.
///
/// [table] must come from [kPurgeableTableNames]; the server refuses anything
/// else, `_photos` above all — see [cleanupUnreferencedPhotos].
Future<MaintenanceRowsResult> purgeInternalTable({required Server server, required String table}) {
  return server.maintenance.purgeTable(body: PurgeTableBody(table: table));
}

/// Deletes photo rows nothing references, and the file behind each one.
///
/// The one cleanup that is not a purge: a bulk `DELETE` on `_photos` would
/// remove the rows without running the per-row path that deletes their files,
/// orphaning every file it removed a row for.
Future<PhotoCleanupResult> cleanupUnreferencedPhotos({required Server server}) {
  return server.maintenance.cleanupPhotos();
}

/// Rewrites the log database when enough of it is dead space.
///
/// The result's `skipped` reason is the field worth reading: a volume with no
/// headroom reclaims nothing, and without the reason that is indistinguishable
/// from having had nothing to reclaim.
Future<LogSpaceReclamationResult> reclaimLogSpace({required Server server}) {
  return server.maintenance.reclaimLogSpace();
}
