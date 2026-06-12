import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_client/src/db_listen.dart';
import 'package:zonai_schema/zonai_schema.dart';

class Db {
  Db({required this._db}) : listen = DbListen(db: _db);

  final DbDataSource _db;
  final DbListen listen;

  Future<Map<String, Object?>> get({required GetBody body}) async {
    return await _db.get(body: body);
  }

  Future<Paginated<Map<String, Object?>>> list({required ListBody body}) async {
    final data = await _db.list(body: body);

    return Paginated.fromJson(data, (json) => json);
  }

  Future<int> count({required CountBody body}) async {
    return await _db.count(body: body);
  }

  Future<Map<String, Object?>> create({required CreateBody body}) async {
    return await _db.create(body: body);
  }

  Future<Map<String, Object?>> update({required UpdateOneBody body}) async {
    return await _db.update(body: body);
  }

  Future<List<Map<String, Object?>>> updateMany({
    required UpdateBody body,
  }) async {
    return await _db.updateMany(body: body);
  }

  Future<void> delete({required DeleteOneBody body}) async {
    await _db.delete(body: body);
  }

  Future<void> deleteMany({required DeleteBody body}) async {
    await _db.deleteMany(body: body);
  }
}
