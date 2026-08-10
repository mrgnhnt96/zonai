part of '../../client.dart';

class CronDataSourceImpl implements CronDataSource {
  const CronDataSourceImpl({
    required RevaliClient client,
    required Storage storage,
  }) : _client = client,
       _storage = storage;

  final RevaliClient _client;

  final Storage _storage;

  @override
  Future<CronJobList> list({String? authorization}) async {
    final response = await _client.request(
      method: 'GET',
      path: '/crons/list',
      headers: {'authorization': authorization},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return CronJobList.fromJson(Map.from((data as Map)));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<void> run({required String name, String? authorization}) async {
    await _client.request(
      method: 'POST',
      path: '/crons/run',
      headers: {'authorization': authorization},
      query: {'name': name},
    );
  }
}
