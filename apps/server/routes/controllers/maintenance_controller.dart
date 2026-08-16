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

  @Post('reclaim-log-space')
  Future<LogSpaceReclamationResult> reclaimLogSpace({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
  }) {
    return maintenanceHandler.reclaimLogSpace(authorization);
  }
}
