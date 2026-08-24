part of '../../client.dart';

class ApiTokenDataSourceImpl implements ApiTokenDataSource {
  const ApiTokenDataSourceImpl({
    required RevaliClient client,
    required Storage storage,
  }) : _client = client,
       _storage = storage;

  final RevaliClient _client;

  final Storage _storage;

  @override
  Future<Map<String, Object?>> list({String? authorization}) async {
    final response = await _client.request(
      method: 'GET',
      path: '/admin/tokens',
      headers: {'authorization': authorization},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>> create({
    required ApiTokenCreateBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/admin/tokens',
      headers: {'authorization': authorization},
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>> revoke({
    required String id,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/admin/tokens/${id}/revoke',
      headers: {'authorization': authorization},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<void> delete({required String id, String? authorization}) async {
    await _client.request(
      method: 'DELETE',
      path: '/admin/tokens/${id}',
      headers: {'authorization': authorization},
    );
  }
}
