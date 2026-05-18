import '../payloads/create_body.dart';
import '../payloads/delete_body.dart';
import '../payloads/get_body.dart';
import '../payloads/list_body.dart';
import '../payloads/stream_body.dart';
import '../payloads/stream_list_body.dart';
import '../payloads/update_body.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai_schema/zonai_schema.dart';

class DbHandler {
  const DbHandler();

  Future<Map<String, Object?>> get(GetBody body) async {
    return await zonaiDB.read(body.collection, .new(where: body.where));
  }

  Future<Paginated<Map<String, Object?>>> list(ListBody body) async {
    return await zonaiDB.list(
      body.collection,
      .new(where: body.where, limit: body.limit, offset: body.offset),
    );
  }

  Future<Map<String, Object?>> create(CreateBody body) async {
    return await zonaiDB.create(body.collection, .new(object: body.object));
  }

  Future<Map<String, Object?>> update(UpdateOneBody body) async {
    final result = await zonaiDB.update(
      body.collection,
      .new(where: body.where, limit: body.limit, updates: body.updates),
    );

    return result.single;
  }

  Future<List<Map<String, Object?>>> updateMany(UpdateBody body) async {
    return await zonaiDB.update(
      body.collection,
      .new(where: body.where, limit: body.limit, updates: body.updates),
    );
  }

  Future<void> delete(DeleteOneBody body) async {
    await zonaiDB.delete('items', .new(where: body.where, limit: body.limit));
  }

  Future<void> deleteMany(DeleteBody body) async {
    await zonaiDB.delete('items', .new(where: body.where, limit: body.limit));
  }

  Stream<Map<String, Object?>> streamOne(StreamBody body) {
    return zonaiDB.streamOne(body.collection, .new(where: body.where));
  }

  Stream<List<Map<String, Object?>>> streamList(StreamListBody body) {
    return zonaiDB.streamList(
      body.collection,
      .new(where: body.where, limit: body.limit, offset: body.offset),
    );
  }
}
