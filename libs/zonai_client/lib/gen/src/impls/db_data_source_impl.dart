part of '../../client.dart';

class DbDataSourceImpl implements DbDataSource {
  const DbDataSourceImpl({
    required RevaliClient client,
    required Storage storage,
  }) : _client = client,
       _storage = storage;

  final RevaliClient _client;

  final Storage _storage;

  @override
  Future<Map<String, Object?>> get({
    required GetBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'GET',
      path: '/db',
      headers: {'authorization': authorization},
      query: {'body': body},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>> list({
    required ListBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'GET',
      path: '/db/list',
      headers: {'authorization': authorization},
      query: {'body': body},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<int> count({required CountBody body, String? authorization}) async {
    final response = await _client.request(
      method: 'GET',
      path: '/db/count',
      headers: {'authorization': authorization},
      query: {'body': body},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final int data}) {
      return data;
    }

    throw Exception('Invalid response');
  }

  @override
  Stream<Map<String, Object?>> streamOne({
    required StreamBody body,
    String? authorization,
  }) async* {
    final response = await _client.request(
      method: 'GET',
      path: '/db/stream',
      headers: {'authorization': authorization},
      body: body,
    );

    final stream = response.transform(utf8.decoder);

    yield* stream
        .map((event) {
          if (jsonDecode(event) case {'data': final Map data}) {
            return data.map((key, value) => MapEntry((key as String), value));
          }

          throw Exception('Invalid response');
        })
        .handleError((_) {
          // do nothing
        });
  }

  @override
  Stream<List<Map<String, Object?>>> streamList({
    required StreamListBody body,
    String? authorization,
  }) async* {
    final response = await _client.request(
      method: 'GET',
      path: '/db/stream/list',
      headers: {'authorization': authorization},
      body: body,
    );

    final stream = response.transform(utf8.decoder);

    yield* stream
        .map((event) {
          if (jsonDecode(event) case {'data': final List data}) {
            return data
                .map(
                  (e) => (e as Map).map(
                    (key, value) => MapEntry((key as String), value),
                  ),
                )
                .toList();
          }

          throw Exception('Invalid response');
        })
        .handleError((_) {
          // do nothing
        });
  }

  @override
  Stream<int> streamCount({
    required StreamCountBody body,
    String? authorization,
  }) async* {
    final response = await _client.request(
      method: 'GET',
      path: '/db/stream/count',
      headers: {'authorization': authorization},
      body: body,
    );

    final stream = response.transform(utf8.decoder);

    yield* stream
        .map((event) {
          if (jsonDecode(event) case {'data': final int data}) {
            return data;
          }

          throw Exception('Invalid response');
        })
        .handleError((_) {
          // do nothing
        });
  }

  @override
  Future<Map<String, Object?>> create({
    required CreateBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/db',
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
  Future<List<Map<String, Object?>>> createMany({
    required CreateManyBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/db/many',
      headers: {'authorization': authorization},
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final List data}) {
      return data
          .map(
            (e) => (e as Map).map(
              (key, value) => MapEntry((key as String), value),
            ),
          )
          .toList();
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>> update({
    required UpdateOneBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/db',
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
  Future<List<Map<String, Object?>>> updateMany({
    required UpdateBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/db/many',
      headers: {'authorization': authorization},
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final List data}) {
      return data
          .map(
            (e) => (e as Map).map(
              (key, value) => MapEntry((key as String), value),
            ),
          )
          .toList();
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>> custom({
    required String operation,
    required CustomOneBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/db/custom/${operation}',
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
  Future<List<Map<String, Object?>>> customMany({
    required String operation,
    required CustomBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/db/custom/${operation}/many',
      headers: {'authorization': authorization},
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final List data}) {
      return data
          .map(
            (e) => (e as Map).map(
              (key, value) => MapEntry((key as String), value),
            ),
          )
          .toList();
    }

    throw Exception('Invalid response');
  }

  @override
  Future<void> delete({
    required DeleteOneBody body,
    String? authorization,
  }) async {
    await _client.request(
      method: 'DELETE',
      path: '/db',
      headers: {'authorization': authorization},
      body: body,
    );
  }

  @override
  Future<void> deleteMany({
    required DeleteBody body,
    String? authorization,
  }) async {
    await _client.request(
      method: 'DELETE',
      path: '/db/many',
      headers: {'authorization': authorization},
      body: body,
    );
  }
}
