import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/exceptions/crud_exception.dart';
import 'package:zonai_schema/zonai_schema.dart';

class DbHandler {
  const DbHandler();

  Future<Map<String, Object?>> get(String? authorization, GetBody body) async {
    return await zonaiDB.read(
      body.table,
      .new(
        where: body.where,
        expand: body.expand,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );
  }

  Future<Paginated<Map<String, Object?>>> list(
    String? authorization,
    ListBody body,
  ) async {
    return await zonaiDB.list(
      body.table,
      .new(
        where: body.where,
        limit: body.limit,
        offset: body.offset,
        orderBy: body.orderBy,
        groupBy: body.groupBy,
        expand: body.expand,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );
  }

  Future<Map<String, Object?>> create(
    String? authorization,
    CreateBody body,
  ) async {
    return await zonaiDB.create(
      body.table,
      .new(object: body.object, jwt: _parseBearerAuthorization(authorization)),
    );
  }

  Future<List<Map<String, Object?>>> createMany(
    String? authorization,
    CreateManyBody body,
  ) async {
    return await zonaiDB.createMany(
      body.table,
      .new(
        objects: body.objects,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );
  }

  Future<Map<String, Object?>> update(
    String? authorization,
    UpdateOneBody body,
  ) async {
    final result = await zonaiDB.update(
      body.table,
      .new(
        where: body.where,
        limit: body.limit,
        updates: body.updates,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );

    // Nothing matched. That is an ordinary outcome of a conditional update
    // ("close it if it is still open"), not a server fault -- `StateError`
    // here reported it as a 500, so a caller could not tell "the row is gone"
    // from "zonai broke". `RecordNotFoundException` is already mapped to 404
    // by `exception_catcher.dart`.
    if (result.isEmpty) {
      throw RecordNotFoundException(table: body.table);
    }
    return result.first;
  }

  Future<List<Map<String, Object?>>> updateMany(
    String? authorization,
    UpdateBody body,
  ) async {
    return await zonaiDB.update(
      body.table,
      .new(
        where: body.where,
        limit: body.limit,
        updates: body.updates,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );
  }

  Future<Map<String, Object?>> custom(
    String? authorization,
    String operation,
    CustomOneBody body,
  ) async {
    final result = await zonaiDB.custom(
      body.table,
      .new(
        operation: operation,
        where: body.where,
        limit: body.limit,
        updates: body.updates,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );

    // Same reasoning as `update` above: no row matched is a 404, not a 500.
    if (result.isEmpty) {
      throw RecordNotFoundException(table: body.table);
    }
    return result.first;
  }

  Future<List<Map<String, Object?>>> customMany(
    String? authorization,
    String operation,
    CustomBody body,
  ) async {
    return await zonaiDB.custom(
      body.table,
      .new(
        operation: operation,
        where: body.where,
        limit: body.limit,
        updates: body.updates,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );
  }

  Future<void> delete(String? authorization, DeleteOneBody body) async {
    await zonaiDB.delete(
      body.table,
      .new(
        where: body.where,
        limit: body.limit,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );
  }

  Future<void> deleteMany(String? authorization, DeleteBody body) async {
    await zonaiDB.delete(
      body.table,
      .new(
        where: body.where,
        limit: body.limit,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );
  }

  Stream<Map<String, Object?>> streamOne(
    String? authorization,
    StreamBody body,
  ) {
    return zonaiDB.streamOne(
      body.table,
      .new(
        where: body.where,
        expand: body.expand,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );
  }

  Stream<List<Map<String, Object?>>> streamList(
    String? authorization,
    StreamListBody body,
  ) {
    return zonaiDB.streamList(
      body.table,
      .new(
        where: body.where,
        limit: body.limit,
        offset: body.offset,
        orderBy: body.orderBy,
        groupBy: body.groupBy,
        expand: body.expand,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );
  }

  Stream<int> streamCount(String? authorization, StreamCountBody body) {
    return zonaiDB.streamCount(
      body.table,
      .new(where: body.where, jwt: _parseBearerAuthorization(authorization)),
    );
  }

  String? _parseBearerAuthorization(String? authorizationHeader) {
    if (authorizationHeader == null) {
      return null;
    }

    final trimmed = authorizationHeader.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    const prefix = 'Bearer ';
    if (trimmed.length >= prefix.length &&
        trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      return trimmed.substring(prefix.length).trim();
    }

    return null;
  }

  Future<int> count(String? authorization, CountBody body) async {
    return await zonaiDB.count(
      body.table,
      .new(where: body.where, jwt: _parseBearerAuthorization(authorization)),
    );
  }
}
