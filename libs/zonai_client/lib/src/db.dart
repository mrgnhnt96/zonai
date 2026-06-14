import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_client/src/db_listen.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/src/types/paginated.dart';

class Db {
  Db({required this._db}) : listen = DbListen(db: _db);

  final DbDataSource _db;
  final DbListen listen;

  Future<Map<String, Object?>> get({
    required GetBody body,
    String? authorization,
  }) async {
    return await _db.get(body: body, authorization: authorization);
  }

  Future<Paginated<Map<String, Object?>>> list({
    required ListBody body,
    String? authorization,
  }) async {
    final data = await _db.list(body: body, authorization: authorization);

    return Paginated.fromJson(data, (json) => json);
  }

  Future<int> count({
    required CountBody body,
    String? authorization,
  }) async {
    return await _db.count(body: body, authorization: authorization);
  }

  Future<Map<String, Object?>> create({
    required CreateBody body,
    String? authorization,
  }) async {
    return await _db.create(body: body, authorization: authorization);
  }

  Future<List<Map<String, Object?>>> createMany({
    required CreateManyBody body,
    String? authorization,
  }) async {
    return await _db.createMany(body: body, authorization: authorization);
  }

  Future<Map<String, Object?>> update({
    required UpdateOneBody body,
    String? authorization,
  }) async {
    return await _db.update(body: body, authorization: authorization);
  }

  Future<List<Map<String, Object?>>> updateMany({
    required UpdateBody body,
    String? authorization,
  }) async {
    return await _db.updateMany(body: body, authorization: authorization);
  }

  Future<void> delete({
    required DeleteOneBody body,
    String? authorization,
  }) async {
    await _db.delete(body: body, authorization: authorization);
  }

  Future<void> deleteMany({
    required DeleteBody body,
    String? authorization,
  }) async {
    await _db.deleteMany(body: body, authorization: authorization);
  }
}
