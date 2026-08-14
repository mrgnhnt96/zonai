import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_schema/payloads.dart';

class DbListen {
  const DbListen({required this._db});

  final DbDataSource _db;

  Stream<T> one<T>({
    required StreamBody body,
    required T Function(Map<String, Object?>) fromJson,
    String? authorization,
  }) async* {
    yield* (await _db.streamOne(
      body: body,
      authorization: authorization,
    )).map(fromJson);
  }

  Stream<List<T>> list<T>({
    required StreamListBody body,
    required T Function(Map<String, Object?>) fromJson,
    String? authorization,
  }) async* {
    yield* (await _db.streamList(
      body: body,
      authorization: authorization,
    )).map((items) => items.map(fromJson).toList());
  }

  Stream<int> count({
    required StreamCountBody body,
    String? authorization,
  }) async* {
    yield* await _db.streamCount(body: body, authorization: authorization);
  }
}
