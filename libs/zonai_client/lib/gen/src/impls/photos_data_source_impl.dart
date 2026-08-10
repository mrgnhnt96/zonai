part of '../../client.dart';

class PhotosDataSourceImpl implements PhotosDataSource {
  const PhotosDataSourceImpl({
    required RevaliClient client,
    required Storage storage,
  }) : _client = client,
       _storage = storage;

  final RevaliClient _client;

  final Storage _storage;

  @override
  Stream<List<int>> view({required String id, String? authorization}) async* {
    final response = await _client.request(
      method: 'GET',
      path: '/img/${id}',
      headers: {'authorization': authorization},
    );

    yield* response.handleError((_) {
      // do nothing
    });
  }

  @override
  Future<Map<String, Object?>> create({
    required Stream<List<int>> image,
    required PhotoCreateMeta meta,
    String? authorization,
    String? contentType,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/img',
      headers: {'authorization': authorization, 'content-type': contentType},
      query: {'meta': meta},
      body: image,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<void> update({
    required String id,
    required Stream<List<int>> image,
    String? authorization,
  }) async {
    await _client.request(
      method: 'PATCH',
      path: '/img/${id}',
      headers: {'authorization': authorization},
      body: image,
    );
  }

  @override
  Future<void> delete({required String id, String? authorization}) async {
    await _client.request(
      method: 'DELETE',
      path: '/img/${id}',
      headers: {'authorization': authorization},
    );
  }
}
