part of '../../client.dart';

class EmailDataSourceImpl implements EmailDataSource {
  const EmailDataSourceImpl({
    required RevaliClient client,
    required Storage storage,
  }) : _client = client,
       _storage = storage;

  final RevaliClient _client;

  final Storage _storage;

  @override
  Future<void> send({required Email body}) async {
    await _client.request(method: 'POST', path: '/email', body: body);
  }
}
