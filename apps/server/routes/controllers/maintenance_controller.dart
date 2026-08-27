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
  ///
  /// Introduced in 0.9.0.
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
  ///
  /// **307, not the 302 that was asked for, and the difference is the whole
  /// point of keeping this route.** A 302 is not method-preserving: per the
  /// Fetch standard a browser rewrites a redirected `POST` into a `GET` and
  /// drops the body, and every route on this controller is `POST`-only on
  /// purpose (see the class doc). A 302 therefore does not reach
  /// [reclaimSpace] at all -- the second request arrives as a `GET`,
  /// `Router._findMatch` matches on `(method, segments)` and finds nothing,
  /// and the dashboard's one "Reclaim log space" button gets a 404 on the
  /// path that exists solely for compatibility.
  ///
  /// Measured, not reasoned. `e2e/legacy_reclaim_redirect` serves this route
  /// tree from the real [Router] and records the method and path the SERVER
  /// received. Against 302, Chrome 151 sent
  /// `POST /dashboard/maintenance/reclaim-log-space` and then
  /// `GET /dashboard/maintenance/reclaim-space?...` -> 404. Against 307 the
  /// second request is a `POST`, carries both arguments, and reaches the
  /// handler. 307 is the smallest change that makes the kept route work.
  ///
  /// One caller this does not rescue: `dart:io`. Its
  /// `HttpClientResponse.isRedirect` is false for a `POST` receiving anything
  /// but 303, so `package:http`'s `IOClient` follows neither 302 nor 307 nor
  /// 308 -- a Dart consumer of the generated client sees the raw redirect
  /// whatever this number is. That is a limitation of `dart:io`, not of this
  /// route, and it does not touch the browser, which is the only caller of
  /// this path.
  ///
  /// The redirect ships in 0.9.0. Through 0.8.5 this route answered directly.
  @Redirect(
    '/dashboard/maintenance/reclaim-space?target=logdb&min_reclaimable_bytes=16777216',
    307,
  )
  @Post('reclaim-log-space')
  Future<LogSpaceReclamationResult> reclaimLogSpace({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
  }) {
    return maintenanceHandler.reclaimLogSpace(authorization);
  }
}
