import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

/// Default photo upload limits when SSR does not override [photosConfigProvider].
final defaultPhotosConfig = PhotosConfig();

/// Photo upload limits from [AppConfig], seeded during SSR.
final photosConfigProvider = Provider<PhotosConfig>((ref) => defaultPhotosConfig);

/// The upload limits the browser needs. `storage` is left out: the dashboard
/// never reads it, and the bucket's endpoint has no reason to be in the page.
Map<String, dynamic> photosConfigToJson(PhotosConfig config) => {
  ...config.toJson()..remove('storage'),
  'requiredMimeType': config.requiredMimeType,
};

PhotosConfig photosConfigFromJson(Map<String, dynamic> json) => PhotosConfig(
  maxBytes: json['maxBytes'] as int?,
  requiredMimeType: json['requiredMimeType'] as bool? ?? true,
  allowedMimeTypes: json['allowedMimeTypes'] == null
      ? null
      : [
          for (final mime in json['allowedMimeTypes'] as List<dynamic>)
            ImageMimeType.fromContentType(mime as String) ??
                (throw ArgumentError.value(mime, 'allowedMimeTypes', 'Unsupported image mime type')),
        ],
);
