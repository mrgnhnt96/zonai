import 'dart:typed_data';

import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_schema/payloads.dart';

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
  final resolved = (config.requiredMimeType && declared != null) ? declared : (detected ?? declared);

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
void validatePhotoBytes({required Uint8List bytes, required String mimeType, required PhotosConfig config}) {
  resolveUploadMimeType(bytes: bytes, mimeType: mimeType, config: config);
}

/// Creates a photo for [table] and returns the new photo id.
Future<String> createPhoto({
  required ZonaiClient client,
  required String table,
  required Uint8List bytes,
  required String mimeType,
  required PhotosConfig config,
}) async {
  final resolved = resolveUploadMimeType(bytes: bytes, mimeType: mimeType, config: config);

  final result = await client.photos.create(
    image: Stream.value(bytes),
    meta: PhotoCreateMeta(table: table),
    contentType: resolved.mimeType,
  );

  if (result['id'] is! String) {
    throw StateError('Photo upload returned an unexpected response');
  }
  return result['id'] as String;
}

/// Replaces image bytes for an existing photo.
Future<void> patchPhoto({
  required ZonaiClient client,
  required String id,
  required Uint8List bytes,
  required String mimeType,
  required PhotosConfig config,
}) async {
  final resolved = resolveUploadMimeType(bytes: bytes, mimeType: mimeType, config: config);

  await client.photos.update(image: Stream.value(bytes), id: id, contentType: resolved.mimeType);
}

/// Deletes a photo. Failures are ignored (best-effort orphan cleanup).
Future<void> deletePhotoBestEffort({required ZonaiClient client, required String id}) async {
  try {
    await client.photos.delete(id: id);
  } on Object {
    // ignore
  }
}
