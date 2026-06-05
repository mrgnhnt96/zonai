import 'dart:convert';
import 'dart:typed_data';

import 'package:revali_client/revali_client.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';
import 'package:zonai_web/utils/zonai_cookie.dart';

/// Resolves the Content-Type to send for an upload (may differ from [mimeType]).
ImageMimeType resolveUploadMimeType({
  required Uint8List bytes,
  required String mimeType,
  required PhotosConfig config,
}) {
  if (config.maxBytes case final limit? when bytes.length > limit) {
    throw FormatException('Image exceeds maximum size of $limit bytes');
  }

  final declared = ImageMimeType.fromContentType(mimeType);
  final detected = ImageMimeType.detect(bytes);
  final resolved = (config.requiredMimeType && declared != null)
      ? declared
      : (detected ?? declared);

  if (resolved == null) {
    throw FormatException('Could not detect image type');
  }

  if (config.allowedMimeTypes case final allowed? when !allowed.contains(resolved)) {
    throw FormatException('Image type not allowed: ${resolved.mimeType}');
  }

  if (config.requiredMimeType && declared != null && detected != null && declared != detected) {
    throw FormatException('Image content does not match declared type');
  }

  return resolved;
}

/// Validates image bytes against [config] before upload.
void validatePhotoBytes({
  required Uint8List bytes,
  required String mimeType,
  required PhotosConfig config,
}) {
  resolveUploadMimeType(bytes: bytes, mimeType: mimeType, config: config);
}

/// Creates a photo for [table] and returns the new photo id.
Future<String> createPhoto({
  required String table,
  required Uint8List bytes,
  required String mimeType,
  required PhotosConfig config,
}) async {
  final resolved = resolveUploadMimeType(bytes: bytes, mimeType: mimeType, config: config);

  final token = ZonaiCookie.authToken.read();
  final headers = <String, String>{
    'content-type': resolved.mimeType,
    if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
  };

  final response = await revaliServer.client.request(
    method: 'POST',
    path: '/img',
    query: {'meta': PhotoCreateMeta(table: table)},
    headers: headers,
    body: bytes,
  );

  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ServerException(
      message: 'Photo upload failed (${response.statusCode})',
      statusCode: response.statusCode,
      body: body,
    );
  }

  final decoded = jsonDecode(body);
  final data = decoded is Map ? decoded['data'] ?? decoded : null;
  if (data is! Map || data['id'] is! String) {
    throw StateError('Photo upload returned an unexpected response');
  }
  return data['id'] as String;
}

/// Replaces image bytes for an existing photo.
Future<void> patchPhoto({
  required String id,
  required Uint8List bytes,
  required String mimeType,
  required PhotosConfig config,
}) async {
  final resolved = resolveUploadMimeType(bytes: bytes, mimeType: mimeType, config: config);

  final token = ZonaiCookie.authToken.read();
  final headers = <String, String>{
    'content-type': resolved.mimeType,
    if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
  };

  final response = await revaliServer.client.request(
    method: 'PATCH',
    path: '/img/$id',
    headers: headers,
    body: bytes,
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    final body = await response.transform(utf8.decoder).join();
    throw ServerException(
      message: 'Photo update failed (${response.statusCode})',
      statusCode: response.statusCode,
      body: body,
    );
  }
}

/// Deletes a photo. Failures are ignored (best-effort orphan cleanup).
Future<void> deletePhotoBestEffort(String id) async {
  try {
    final token = ZonaiCookie.authToken.read();
    final headers = <String, String>{
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };

    final response = await revaliServer.client.request(
      method: 'DELETE',
      path: '/img/$id',
      headers: headers,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // ignore
    }
  } on Object {
    // ignore
  }
}
