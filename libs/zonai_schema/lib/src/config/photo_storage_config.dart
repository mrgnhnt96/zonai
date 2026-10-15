/// Where the server keeps uploaded photos, as [PhotosConfig.storage] selects.
///
/// This only describes the backend. The server does the reading and writing,
/// so nothing here needs an HTTP client, and no credential is part of it:
/// an S3 key pair is read from the server's environment at runtime (see
/// [S3PhotoStorage]) so it is never compiled into a binary.
///
/// [PhotosConfig.storage]: PhotosConfig
sealed class PhotoStorageConfig {
  const PhotoStorageConfig();

  factory PhotoStorageConfig.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      LocalPhotoStorage._type => const LocalPhotoStorage(),
      S3PhotoStorage._type => S3PhotoStorage(
        endpoint: json['endpoint'] as String,
        bucket: json['bucket'] as String,
        region: json['region'] as String? ?? S3PhotoStorage.defaultRegion,
        publicBaseUrl: json['publicBaseUrl'] as String?,
      ),
      final type => throw ArgumentError.value(
        type,
        'type',
        'Unknown photo storage',
      ),
    };
  }

  Map<String, dynamic> toJson();
}

/// Photos as files in the project's images directory, on the server's disk.
///
/// The default.
final class LocalPhotoStorage extends PhotoStorageConfig {
  const LocalPhotoStorage();

  static const _type = 'local';

  @override
  Map<String, dynamic> toJson() => {'type': _type};

  @override
  bool operator ==(Object other) => other is LocalPhotoStorage;

  @override
  int get hashCode => _type.hashCode;
}

/// Photos as objects in an S3-compatible bucket, such as Cloudflare R2.
///
/// For R2, [endpoint] is `https://<account id>.r2.cloudflarestorage.com` and
/// [region] stays `auto`. Objects are addressed path-style
/// (`<endpoint>/<bucket>/<key>`), which R2, MinIO and AWS S3 all accept.
///
/// The key pair is read from the server's environment, never from here:
/// [accessKeyIdVariable] and [secretAccessKeyVariable]. The server refuses to
/// start when this backend is selected and either is missing, rather than
/// starting and failing every upload.
final class S3PhotoStorage extends PhotoStorageConfig {
  const S3PhotoStorage({
    required this.endpoint,
    required this.bucket,
    this.region = defaultRegion,
    this.publicBaseUrl,
  });

  static const _type = 's3';

  /// R2's region. AWS S3 needs the bucket's real region instead.
  static const defaultRegion = 'auto';

  /// The environment variable holding the access key id.
  static const accessKeyIdVariable = 'S3_ACCESS_KEY_ID';

  /// The environment variable holding the secret access key.
  static const secretAccessKeyVariable = 'S3_SECRET_ACCESS_KEY';

  /// The S3 API's base URL, without the bucket.
  final String endpoint;

  final String bucket;

  /// The region requests are signed for.
  final String region;

  /// A public URL the bucket's objects are also served from, such as an R2
  /// custom domain, without a trailing key.
  ///
  /// Not used to serve photos yet; `GET /img/:id` streams from the bucket.
  final String? publicBaseUrl;

  @override
  Map<String, dynamic> toJson() => {
    'type': _type,
    'endpoint': endpoint,
    'bucket': bucket,
    'region': region,
    'publicBaseUrl': publicBaseUrl,
  };

  /// What makes this backend unusable, if anything.
  ///
  /// [environment] is the server's, checked for the key pair. `null` skips
  /// that check, for a caller that only has the config.
  List<String> errors({Map<String, String>? environment}) {
    bool isHttpUrl(String value) {
      final uri = Uri.tryParse(value.trim());
      return uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty;
    }

    bool isSet(String name) => environment?[name]?.trim().isNotEmpty ?? false;

    return [
      if (!isHttpUrl(endpoint))
        'photos.storage.endpoint must be an http(s) URL (got "$endpoint")',
      if (bucket.trim().isEmpty) 'photos.storage.bucket is empty',
      if (region.trim().isEmpty) 'photos.storage.region is empty',
      if (publicBaseUrl case final url? when !isHttpUrl(url))
        'photos.storage.publicBaseUrl must be an http(s) URL (got "$url")',
      if (environment != null)
        for (final name in [accessKeyIdVariable, secretAccessKeyVariable])
          if (!isSet(name))
            '$name is empty — set it in the server\'s environment to use '
                'S3 photo storage',
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is S3PhotoStorage &&
      other.endpoint == endpoint &&
      other.bucket == bucket &&
      other.region == region &&
      other.publicBaseUrl == publicBaseUrl;

  @override
  int get hashCode => Object.hash(endpoint, bucket, region, publicBaseUrl);
}
