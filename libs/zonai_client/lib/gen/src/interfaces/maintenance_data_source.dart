part of '../../interfaces.dart';

abstract interface class MaintenanceDataSource {
  const MaintenanceDataSource();

  Future<MaintenanceRowsResult> purgeLogs({
    required PurgeLogsBody body,
    String? authorization,
  });
  Future<MaintenanceRowsResult> purgeTable({
    required PurgeTableBody body,
    String? authorization,
  });
  Future<PhotoCleanupResult> cleanupPhotos({String? authorization});
  Future<SpaceReclamationResult> reclaimSpace({
    required String target,
    required int minReclaimableBytes,
    String? authorization,
  });
  Future<LogSpaceReclamationResult> reclaimLogSpace({String? authorization});
}
