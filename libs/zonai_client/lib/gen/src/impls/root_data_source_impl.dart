part of '../../client.dart';

class RootDataSourceImpl implements RootDataSource {
  const RootDataSourceImpl({
    required RevaliClient client,
    required Storage storage,
  }) : _client = client,
       _storage = storage;

  final RevaliClient _client;

  final Storage _storage;

  @override
  Future<void> health() async {
    await _client.request(method: 'GET', path: '/health');
  }

  @override
  Stream<List<int>> favicon() async* {
    final response = await _client.request(method: 'GET', path: '/favicon.ico');

    yield* response.handleError((_) {
      // do nothing
    });
  }

  @override
  Future<String> swaggerJson() async {
    final response = await _client.request(
      method: 'GET',
      path: '/swagger.json',
    );

    return await response.transform(utf8.decoder).join();
  }

  @override
  Future<String> swaggerYaml() async {
    final response = await _client.request(
      method: 'GET',
      path: '/swagger.yaml',
    );

    return await response.transform(utf8.decoder).join();
  }
}
