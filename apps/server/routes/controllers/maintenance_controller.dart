import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/src/handlers/maintenance_handler.dart';
import 'package:zonai_schema/src/payloads/maintenance_actions.dart';

/// The Maintenance screen's cleanup verbs.
///
/// Its own controller rather than more methods on [DashboardController]: the
/// dashboard is a read-only surface that a browser polls on a timer, and every
/// route here deletes rows or rewrites a database file. Keeping them apart
/// means "is this endpoint destructive?" is answered by which file it lives
/// in.
///
/// All `POST`, including the ones that could be argued into `GET`. None of
/// these are safe or idempotent in the HTTP sense, and a `GET` that empties a
/// table is one prefetch away from doing it unasked.
@Controller('dashboard/maintenance')
class MaintenanceController {
  const MaintenanceController({required this.maintenanceHandler});

  final MaintenanceHandler maintenanceHandler;

  @Post('purge-logs')
  Future<MaintenanceRowsResult> purgeLogs({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required PurgeLogsBody body,
  }) {
    return maintenanceHandler.purgeLogs(authorization, body: body);
  }

  @Post('purge-table')
  Future<MaintenanceRowsResult> purgeTable({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required PurgeTableBody body,
  }) {
    return maintenanceHandler.purgeTable(authorization, body: body);
  }

  @Post('cleanup-photos')
  Future<PhotoCleanupResult> cleanupPhotos({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
  }) {
    return maintenanceHandler.cleanupPhotos(authorization);
  }

  /// Reclaims space from the database the caller names.
  ///
  /// Arguments in the query string rather than a body, and that is forced
  /// rather than a style choice: [reclaimLogSpace] below redirects onto this
  /// route, and a 3xx carries a `Location` header and no body, so arguments
  /// the redirect has to carry can only live in the URL. `@Query` on a `POST`
  /// is the established shape here -- see `CronController.run`.
  @Post('reclaim-space')
  Future<SpaceReclamationResult> reclaimSpace({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Query('target') required String target,
    @Query('min_reclaimable_bytes') required int minReclaimableBytes,
  }) {
    return maintenanceHandler.reclaimSpace(
      authorization,
      target: target,
      minReclaimableBytes: minReclaimableBytes,
    );
  }

  /// The log-only reclaim, kept as a redirect onto [reclaimSpace].
  ///
  /// **The body below never runs.** `RunRedirect` is called from
  /// `revali_router`'s `Router._handle` *before* `execute.run()`, so a route
  /// carrying `@Redirect` answers with the `Location` response and the method
  /// is never invoked. The method stays because the route stays: the generated
  /// client exposes `reclaimLogSpace` against this path, and removing either
  /// would break a client that has not been regenerated.
  ///
  /// The arguments in the target are the log database and
  /// `kCronReclaimFloorBytes` (16 MiB, written out because `apps/server` does
  /// not depend on the constant), so the legacy path behaves exactly as it did
  /// before. The `Location` is absolute so the result does not depend on how
  /// the requesting URL's last segment resolves.
  @Redirect(
    '/dashboard/maintenance/reclaim-space?target=logdb&min_reclaimable_bytes=16777216',
    302,
  )
  @Post('reclaim-log-space')
  Future<LogSpaceReclamationResult> reclaimLogSpace({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
  }) {
    return maintenanceHandler.reclaimLogSpace(authorization);
  }
}
