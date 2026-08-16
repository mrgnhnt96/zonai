part of '../../client.dart';

class DashboardDataSourceImpl implements DashboardDataSource {
  const DashboardDataSourceImpl({
    required RevaliClient client,
    required Storage storage,
  }) : _client = client,
       _storage = storage;

  final RevaliClient _client;

  final Storage _storage;

  @override
  Future<DashboardMetrics> metrics({
    int? since,
    bool? excludeAdmin,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'GET',
      path: '/dashboard/metrics',
      headers: {'authorization': authorization},
      query: {'since': since, 'exclude_admin': excludeAdmin},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return DashboardMetrics.fromJson(Map.from((data as Map)));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<StorageMetrics> storage({String? authorization}) async {
    final response = await _client.request(
      method: 'GET',
      path: '/dashboard/storage',
      headers: {'authorization': authorization},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return StorageMetrics.fromJson(Map.from((data as Map)));
    }

    throw Exception('Invalid response');
  }
}
