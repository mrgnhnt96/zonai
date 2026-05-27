class PhotosConfig {
  const PhotosConfig({required this.maxBytes, required this.allowedMimeTypes});

  factory PhotosConfig.fromJson(Map<String, dynamic> json) => PhotosConfig(
    maxBytes: json['maxBytes'] as int,
    allowedMimeTypes: [
      for (final mimeType in json['allowedMimeTypes'] as List<dynamic>)
        mimeType as String,
    ],
  );

  /// The maximum number of bytes allowed for a photo upload.
  ///
  /// If not set, there is no limit. (This is NOT recommended.)
  final int? maxBytes;

  /// The allowed mime types for a photo upload.
  ///
  /// If not set, all mime types are allowed.
  final List<String>? allowedMimeTypes;

  Map<String, dynamic> toJson() => {
    'maxBytes': maxBytes,
    'allowedMimeTypes': allowedMimeTypes,
  };
}
