/// Supported image formats for photo uploads.
enum ImageMimeType {
  jpeg(
    mimeType: 'image/jpeg',
    fileExtension: 'jpg',
    magicBytes: [0xFF, 0xD8, 0xFF],
  ),
  png(
    mimeType: 'image/png',
    fileExtension: 'png',
    magicBytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  ),
  gif(
    mimeType: 'image/gif',
    fileExtension: 'gif',
    magicBytes: [0x47, 0x49, 0x46, 0x38], // GIF8 (87a / 89a)
  ),
  webp(
    mimeType: 'image/webp',
    fileExtension: 'webp',
    magicBytes: [0x52, 0x49, 0x46, 0x46], // RIFF; WEBP at offset 8
  );

  const ImageMimeType({
    required this.mimeType,
    required this.fileExtension,
    required this.magicBytes,
  });

  /// The `Content-Type` value for this image format.
  final String mimeType;

  /// File extension without a leading dot.
  final String fileExtension;

  /// Leading bytes that identify this format.
  ///
  /// [webp] uses [0x52, 0x49, 0x46, 0x46] (`RIFF`); [matchesBytes] also
  /// checks for `WEBP` at offset 8.
  final List<int> magicBytes;

  /// Default set used when [PhotosConfig.allowedMimeTypes] is not configured.
  static const defaultAllowed = values;

  /// Parses a `Content-Type` header value (parameters such as `charset` are
  /// ignored).
  static ImageMimeType? fromContentType(String? contentType) {
    if (contentType == null) {
      return null;
    }

    final normalized = contentType.split(';').first.trim().toLowerCase();
    return _byMimeType[normalized];
  }

  /// Detects the image format from the leading bytes of a file or stream chunk.
  static ImageMimeType? detect(List<int> bytes) {
    for (final type in values) {
      if (type.matchesBytes(bytes)) {
        return type;
      }
    }
    return null;
  }

  /// Whether [bytes] begin with this format's magic signature.
  bool matchesBytes(List<int> bytes) {
    if (bytes.length < magicBytes.length) {
      return false;
    }

    for (var i = 0; i < magicBytes.length; i++) {
      if (bytes[i] != magicBytes[i]) {
        return false;
      }
    }

    return switch (this) {
      webp =>
        bytes.length >= 12 &&
            bytes[8] == 0x57 &&
            bytes[9] == 0x45 &&
            bytes[10] == 0x42 &&
            bytes[11] == 0x50,
      gif => bytes.length >= 6 && (bytes[4] == 0x37 || bytes[4] == 0x39),
      _ => true,
    };
  }

  static final Map<String, ImageMimeType> _byMimeType = {
    for (final type in values) type.mimeType: type,
  };
}
