import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// HTTP API for the internal `_photos` table (view, create, update, delete only).
class PhotoHandler {
  /// Streams the photo, or answers `304 Not Modified` with no body when
  /// [ifNoneMatch] already names its current ETag.
  ///
  /// Every answer carries `Cache-Control: no-cache`, never `immutable` or a
  /// `max-age`: `PATCH /img/:id` replaces the bytes behind the same URL, so a
  /// cache has to revalidate before reusing what it stored, and revalidating
  /// is cheap because the 304 has no body. The directive is `public` only
  /// when a caller with no token could view the photo too. Otherwise it is
  /// `private`, so a shared cache (a CDN, a proxy) never stores a photo and
  /// then hands it to callers the photo rules would refuse.
  ///
  /// When the storage serves photos itself (`S3PhotoStorage.redirect`), the
  /// answer is `302 Found` to that URL instead of the bytes, after the same
  /// rules. A redirect to the public URL is cached like the photo, since its
  /// `Location` changes exactly when the ETag does. A redirect to a presigned
  /// URL is `private, no-store` with no ETag: the link grants access by
  /// itself, so no cache may keep it past the rules or past its expiry.
  Future<Stream<List<int>>> view(
    String? authorization,
    String id,
    String? ifNoneMatch,
    Response response,
  ) async {
    final photo = await zonaiDB.viewPhoto(
      id,
      token: _parseBearerAuthorization(authorization),
    );

    final redirect = photo.redirect;
    if (redirect != null && redirect.presigned) {
      response.headers.set(HttpHeaders.cacheControlHeader, 'private, no-store');
      return _redirect(response, redirect.location);
    }

    final headers = response.headers
      ..set(HttpHeaders.etagHeader, photo.etag)
      ..set(
        HttpHeaders.cacheControlHeader,
        photo.publiclyViewable ? 'public, no-cache' : 'private, no-cache',
      );

    if (ifNoneMatch != null && etagMatches(ifNoneMatch, photo.etag)) {
      response.statusCode = HttpStatus.notModified;
      return const Stream.empty();
    }

    if (redirect != null) return _redirect(response, redirect.location);

    final mime = ImageMimeType.fromFileExtension(photo.extension)?.mimeType;
    if (mime != null) {
      headers
        ..mimeType = mime
        ..set(HttpHeaders.contentDisposition, 'inline');
    }
    return photo.openRead();
  }

  Stream<List<int>> _redirect(Response response, Uri location) {
    response.statusCode = HttpStatus.found;
    response.headers.set(HttpHeaders.locationHeader, location.toString());
    return const Stream.empty();
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

  Future<void> delete({
    required String? authorization,
    required String id,
  }) async {
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

/// Whether an `If-None-Match` header value matches [etag].
///
/// Uses the weak comparison RFC 9110 requires for `If-None-Match`, so a `W/`
/// prefix on either side is ignored. `*` matches any current photo, and the
/// header may list several tags separated by commas.
bool etagMatches(String ifNoneMatch, String etag) {
  String opaque(String tag) {
    final trimmed = tag.trim();
    return trimmed.startsWith('W/') ? trimmed.substring(2) : trimmed;
  }

  final target = opaque(etag);
  for (final candidate in ifNoneMatch.split(',')) {
    final value = candidate.trim();
    if (value == '*' || opaque(value) == target) {
      return true;
    }
  }
  return false;
}
