import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_client/src/db_listen.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/src/types/paginated.dart';

class Db {
  Db({required this._db}) : listen = DbListen(db: _db);

  final DbDataSource _db;
  final DbListen listen;

  Future<T> get<T>({
    required GetBody body,
    required T Function(Map<String, Object?>) fromJson,
    String? authorization,
  }) async {
    final data = await _db.get(body: body, authorization: authorization);
    return fromJson(data);
  }

  Future<Paginated<T>> list<T>({
    required ListBody body,
    required T Function(Map<String, Object?>) fromJson,
    String? authorization,
  }) async {
    final data = await _db.list(body: body, authorization: authorization);

    return Paginated.fromJson(
      Map<String, dynamic>.from(data),
      (json) => fromJson(json.cast<String, Object?>()),
    );
  }

  Future<int> count({required CountBody body, String? authorization}) async {
    return await _db.count(body: body, authorization: authorization);
  }

  Future<T> create<T>({
    required CreateBody body,
    required T Function(Map<String, Object?>) fromJson,
    String? authorization,
  }) async {
    final data = await _db.create(body: body, authorization: authorization);
    return fromJson(data);
  }

  Future<List<T>> createMany<T>({
    required CreateManyBody body,
    required T Function(Map<String, Object?>) fromJson,
    String? authorization,
  }) async {
    final data = await _db.createMany(body: body, authorization: authorization);
    return data.map(fromJson).toList();
  }

  Future<T> update<T>({
    required UpdateOneBody body,
    required T Function(Map<String, Object?>) fromJson,
    String? authorization,
  }) async {
    final data = await _db.update(body: body, authorization: authorization);
    return fromJson(data);
  }

  Future<List<T>> updateMany<T>({
    required UpdateBody body,
    required T Function(Map<String, Object?>) fromJson,
    String? authorization,
  }) async {
    final data = await _db.updateMany(body: body, authorization: authorization);
    return data.map(fromJson).toList();
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
