import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_schema/zonai_schema.dart';

class DbListen {
  const DbListen({required this._db});

  final DbDataSource _db;

  Stream<Map<String, Object?>> one({required StreamBody body}) async* {
    yield* await _db.streamOne(body: body);
  }

  Stream<List<Map<String, Object?>>> list({
    required StreamListBody body,
  }) async* {
    yield* await _db.streamList(body: body);
  }

  Stream<int> count({required StreamCountBody body}) async* {
    yield* await _db.streamCount(body: body);
  }
}
