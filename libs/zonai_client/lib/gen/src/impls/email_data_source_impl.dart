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
  Future<void> send({required Email body, String? authorization}) async {
    await _client.request(
      method: 'POST',
      path: '/email',
      headers: {'authorization': authorization},
      body: body,
    );
  }
}
