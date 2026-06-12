import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_schema/zonai_schema.dart';

class DbListen {
  const DbListen({required this._db});

  final DbDataSource _db;

  Stream<Map<String, Object?>> one({
    required StreamBody body,
    String? authorization,
  }) async* {
    yield* await _db.streamOne(body: body, authorization: authorization);
  }

  Stream<List<Map<String, Object?>>> list({
    required StreamListBody body,
    String? authorization,
  }) async* {
    yield* await _db.streamList(body: body, authorization: authorization);
  }

  Stream<int> count({
    required StreamCountBody body,
    String? authorization,
  }) async* {
    yield* await _db.streamCount(body: body, authorization: authorization);
  }
}
