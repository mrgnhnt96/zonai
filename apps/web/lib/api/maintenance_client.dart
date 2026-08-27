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

/// Rewrites the database behind [target] when enough of it is dead space.
///
/// [target] is a schema identifier from [kReclaimableSchemas] — never a path.
/// A path would be an operator's string arriving from a browser that the
/// server would have to re-validate against the deployment's real files,
/// while a schema name is one of three known values the engine already
/// attaches by. The server checks it against the same set regardless.
///
/// [minReclaimableBytes] is the floor below which the rewrite is not worth
/// doing, and it is deliberately the caller's to choose: an unattended nightly
/// cron and an operator pressing a button do not want the same number. See
/// `kUiReclaimFloorBytes` for the one this app sends.
///
/// The result's `skipped` reason is the field worth reading: a volume with no
/// headroom reclaims nothing, and without the reason that is indistinguishable
/// from having had nothing to reclaim.
Future<SpaceReclamationResult> reclaimSpace({
  required Server server,
  required String target,
  required int minReclaimableBytes,
}) {
  return server.maintenance.reclaimSpace(target: target, minReclaimableBytes: minReclaimableBytes);
}
