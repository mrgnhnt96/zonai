import '../types/image_mime_type.dart';
import 'photo_storage_config.dart';

export 'photo_storage_config.dart';

class PhotosConfig {
  const PhotosConfig({
    this.maxBytes = defaultMaxBytes,
    this.requiredMimeType = true,
    this.allowedMimeTypes = ImageMimeType.defaultAllowed,
    this.storage = const LocalPhotoStorage(),
  });

  /// Reads what [toJson] wrote. A key that is absent takes the constructor's
  /// default; a `null` [maxBytes] or [allowedMimeTypes] that is present means
  /// "no limit", as it does in Dart.
  factory PhotosConfig.fromJson(Map<String, dynamic> json) => PhotosConfig(
    maxBytes: json.containsKey('maxBytes')
        ? json['maxBytes'] as int?
        : defaultMaxBytes,
    requiredMimeType: json['requiredMimeType'] as bool? ?? true,
    allowedMimeTypes: !json.containsKey('allowedMimeTypes')
        ? ImageMimeType.defaultAllowed
        : json['allowedMimeTypes'] == null
        ? null
        : [
            for (final mimeType in json['allowedMimeTypes'] as List<dynamic>)
              ImageMimeType.fromContentType(mimeType as String) ??
                  (throw ArgumentError.value(
                    mimeType,
                    'allowedMimeTypes',
                    'Unsupported image mime type',
                  )),
          ],
    storage: switch (json['storage']) {
      final Map<dynamic, dynamic> storage => PhotoStorageConfig.fromJson(
        Map<String, dynamic>.from(storage),
      ),
      _ => const LocalPhotoStorage(),
    },
  );

  static const defaultMaxBytes = 5 * 1024 * 1024; // 5MB

  /// The maximum number of bytes allowed for a photo upload.
  ///
  /// If not set, there is no limit. (This is NOT recommended.)
  final int? maxBytes;

  /// The allowed mime types for a photo upload.
  ///
  /// If not set, all mime types are allowed.
  final List<ImageMimeType>? allowedMimeTypes;

  /// Require the mime type to be present in the Content-Type header
  /// when uploading a photo.
  ///
  /// When `false`, the mime type will be detected from the "magic bytes" of the image.
  final bool requiredMimeType;

  /// Where uploaded photos are kept: the server's disk by default, or an
  /// S3-compatible bucket with [S3PhotoStorage].
  final PhotoStorageConfig storage;

  Map<String, dynamic> toJson() => {
    'maxBytes': maxBytes,
    'allowedMimeTypes': allowedMimeTypes?.map((type) => type.mimeType).toList(),
    'requiredMimeType': requiredMimeType,
    'storage': storage.toJson(),
  };
}
