import 'package:zonai/deps.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// HTTP API for the internal `_photos` collection (view, create, update, delete only).
class PhotoHandler {
  Stream<List<int>> view(String? authorization, String id) {
    return zonaiDB.getPhoto(
      id,
      token: _parseBearerAuthorization(authorization),
    );
  }

  Future<Map<String, Object?>> create(
    String? authorization,
    PhotoCreateMeta meta,
    String? contentType,
    Stream<List<int>> image,
  ) async {
    return await zonaiDB.createPhoto(
      token: _parseBearerAuthorization(authorization),
      meta: meta,
      contentType: contentType,
      image: image,
    );
  }

  Future<void> update(
    String? authorization,
    Stream<List<int>> image,
    String id,
  ) async {
    await zonaiDB.updatePhoto(
      token: _parseBearerAuthorization(authorization),
      id: id,
      image: image,
    );
  }

  Future<void> delete(String? authorization, String id) async {
    await zonaiDB.deletePhoto(
      token: _parseBearerAuthorization(authorization),
      id: id,
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
