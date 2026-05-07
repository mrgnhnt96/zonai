import 'package:zonai_server/src/payloads/create_body.dart';
import 'package:zonai_server/src/payloads/delete_body.dart';
import 'package:zonai_server/src/payloads/get_body.dart';
import 'package:zonai_server/src/payloads/list_body.dart';
import 'package:zonai_server/src/payloads/stream_body.dart';
import 'package:zonai_server/src/payloads/stream_list_body.dart';
import 'package:zonai_server/src/payloads/update_body.dart';
import 'package:zonai/src/deps/zonai_db.dart';

class DbHandler {
  const DbHandler();

  Future<Map<String, Object?>> get(GetBody body) async {
    final (error, result) = await zonaiDB.view(
      body.collection,
      .new(where: body.where),
    );

    if (error != null || result == null) {
      throw StateError('Failed to get item: $error');
    }

    return result;
  }

  Future<List<Map<String, Object?>>> list(ListBody body) async {
    final (error, result) = await zonaiDB.list(
      body.collection,
      .new(where: body.where, limit: body.limit, offset: body.offset),
    );
    if (error != null || result == null) {
      throw StateError('Failed to list items: $error');
    }
    return result;
  }

  Future<Map<String, Object?>> create(CreateBody body) async {
    final (error, result) = await zonaiDB.create(
      'items',
      .new(object: body.object),
    );

    if (error != null || result == null) {
      throw StateError('Failed to create item: $error');
    }

    return result;
  }

  Future<Map<String, Object?>> update(UpdateOneBody body) async {
    final (error, result) = await zonaiDB.update(
      'items',
      .new(where: body.where, limit: body.limit, updates: body.updates),
    );
    if (error != null || result == null) {
      throw StateError('Failed to update item: $error');
    }

    return result.single;
  }

  Future<List<Map<String, Object?>>> updateMany(UpdateBody body) async {
    final (error, result) = await zonaiDB.update(
      'items',
      .new(where: body.where, limit: body.limit, updates: body.updates),
    );

    if (error != null || result == null) {
      throw StateError('Failed to update items: $error');
    }

    return result;
  }

  Future<void> delete(DeleteOneBody body) async {
    final (error, result) = await zonaiDB.delete(
      'items',
      .new(where: body.where, limit: body.limit),
    );

    if (error != null || result == null) {
      throw StateError('Failed to delete item: $error');
    }
  }

  Future<void> deleteMany(DeleteBody body) async {
    final (error, result) = await zonaiDB.delete(
      'items',
      .new(where: body.where, limit: body.limit),
    );

    if (error != null || result == null) {
      throw StateError('Failed to delete items: $error');
    }
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
