part of '../../client.dart';

class MaintenanceDataSourceImpl implements MaintenanceDataSource {
  const MaintenanceDataSourceImpl({
    required RevaliClient client,
    required Storage storage,
  }) : _client = client,
       _storage = storage;

  final RevaliClient _client;

  final Storage _storage;

  @override
  Future<MaintenanceRowsResult> purgeLogs({
    required PurgeLogsBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/dashboard/maintenance/purge-logs',
      headers: {'authorization': authorization},
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return MaintenanceRowsResult.fromJson(Map.from((data as Map)));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<MaintenanceRowsResult> purgeTable({
    required PurgeTableBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/dashboard/maintenance/purge-table',
      headers: {'authorization': authorization},
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return MaintenanceRowsResult.fromJson(Map.from((data as Map)));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<PhotoCleanupResult> cleanupPhotos({String? authorization}) async {
    final response = await _client.request(
      method: 'POST',
      path: '/dashboard/maintenance/cleanup-photos',
      headers: {'authorization': authorization},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return PhotoCleanupResult.fromJson(Map.from((data as Map)));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<SpaceReclamationResult> reclaimSpace({
    required String target,
    required int minReclaimableBytes,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/dashboard/maintenance/reclaim-space',
      headers: {'authorization': authorization},
      query: {'target': target, 'min_reclaimable_bytes': minReclaimableBytes},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return SpaceReclamationResult.fromJson(Map.from((data as Map)));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<LogSpaceReclamationResult> reclaimLogSpace({
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/dashboard/maintenance/reclaim-log-space',
      headers: {'authorization': authorization},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return LogSpaceReclamationResult.fromJson(Map.from((data as Map)));
    }

    throw Exception('Invalid response');
  }
}
