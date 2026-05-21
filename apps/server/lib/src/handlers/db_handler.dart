import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai_schema/zonai_schema.dart';

class DbHandler {
  const DbHandler();

  Future<Map<String, Object?>> get(String? authorization, GetBody body) async {
    return await zonaiDB.read(
      body.collection,
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
      body.collection,
      .new(
        where: body.where,
        limit: body.limit,
        offset: body.offset,
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
      body.collection,
      .new(object: body.object, jwt: _parseBearerAuthorization(authorization)),
    );
  }

  Future<Map<String, Object?>> update(
    String? authorization,
    UpdateOneBody body,
  ) async {
    final result = await zonaiDB.update(
      body.collection,
      .new(
        where: body.where,
        limit: body.limit,
        updates: body.updates,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );

    return result.single;
  }

  Future<List<Map<String, Object?>>> updateMany(
    String? authorization,
    UpdateBody body,
  ) async {
    return await zonaiDB.update(
      body.collection,
      .new(
        where: body.where,
        limit: body.limit,
        updates: body.updates,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );
  }

  Future<void> delete(String? authorization, DeleteOneBody body) async {
    await zonaiDB.delete(
      'items',
      .new(
        where: body.where,
        limit: body.limit,
        jwt: _parseBearerAuthorization(authorization),
      ),
    );
  }

  Future<void> deleteMany(String? authorization, DeleteBody body) async {
    await zonaiDB.delete(
      'items',
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
      body.collection,
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
      body.collection,
      .new(
        where: body.where,
        limit: body.limit,
        offset: body.offset,
        expand: body.expand,
        jwt: _parseBearerAuthorization(authorization),
      ),
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
}
