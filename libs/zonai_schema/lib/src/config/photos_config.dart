import '../types/image_mime_type.dart';

class PhotosConfig {
  const PhotosConfig({
    this.maxBytes = 5 * 1024 * 1024, // 5MB
    this.requiredMimeType = true,
    this.allowedMimeTypes = ImageMimeType.defaultAllowed,
  });

  factory PhotosConfig.fromJson(Map<String, dynamic> json) => PhotosConfig(
    maxBytes: json['maxBytes'] as int?,
    allowedMimeTypes: json['allowedMimeTypes'] == null
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
  );

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

  Map<String, dynamic> toJson() => {
    'maxBytes': maxBytes,
    'allowedMimeTypes': allowedMimeTypes?.map((type) => type.mimeType).toList(),
  };
}
