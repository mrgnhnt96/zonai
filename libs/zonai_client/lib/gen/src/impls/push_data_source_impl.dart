part of '../../client.dart';

class PushDataSourceImpl implements PushDataSource {
  const PushDataSourceImpl({
    required RevaliClient client,
    required Storage storage,
  }) : _client = client,
       _storage = storage;

  final RevaliClient _client;

  final Storage _storage;

  @override
  Future<PushTestSendResult> sendTest({
    required PushTestSendBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/dashboard/push/test',
      headers: {'authorization': authorization},
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return PushTestSendResult.fromJson(Map.from((data as Map)));
    }

    throw Exception('Invalid response');
  }
}
