import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

void main() {
  const s3 = S3PhotoStorage(
    endpoint: 'https://account.r2.cloudflarestorage.com',
    bucket: 'photos',
    publicBaseUrl: 'https://img.example.com',
  );

  group(PhotosConfig, () {
    test('defaults to local storage', () {
      expect(const PhotosConfig().storage, const LocalPhotoStorage());
    });

    test('round-trips every field through JSON', () {
      const config = PhotosConfig(
        maxBytes: 42,
        requiredMimeType: false,
        allowedMimeTypes: [ImageMimeType.png],
        storage: s3,
      );

      final read = PhotosConfig.fromJson(config.toJson());

      expect(read.maxBytes, 42);
      expect(read.requiredMimeType, isFalse);
      expect(read.allowedMimeTypes, [ImageMimeType.png]);
      expect(read.storage, s3);
    });

    test('keeps "no limit" distinct from an absent key', () {
      final read = PhotosConfig.fromJson({
        'maxBytes': null,
        'allowedMimeTypes': null,
      });
      final absent = PhotosConfig.fromJson({});

      expect(read.maxBytes, isNull);
      expect(read.allowedMimeTypes, isNull);
      expect(absent.maxBytes, PhotosConfig.defaultMaxBytes);
      expect(absent.allowedMimeTypes, ImageMimeType.defaultAllowed);
      expect(absent.requiredMimeType, isTrue);
      expect(absent.storage, const LocalPhotoStorage());
    });
  });

  group(PhotoStorageConfig, () {
    test('S3 defaults the region to R2\'s "auto"', () {
      final read = PhotoStorageConfig.fromJson({
        'type': 's3',
        'endpoint': 'https://e.example.com',
        'bucket': 'b',
      });

      expect(
        read,
        isA<S3PhotoStorage>().having((s) => s.region, 'region', 'auto'),
      );
    });

    test('rejects an unknown type', () {
      expect(
        () => PhotoStorageConfig.fromJson({'type': 'ftp'}),
        throwsArgumentError,
      );
    });
  });

  group(AppConfig, () {
    const base = AppConfig(
      appName: 'app',
      passwordSecret: 'password-secret-that-is-long-enough-123',
      jwtSecret: 'jwt-secret-that-is-long-enough-and-different',
    );
    AppConfig withStorage(PhotoStorageConfig storage) => AppConfig(
      appName: base.appName,
      passwordSecret: base.passwordSecret,
      jwtSecret: base.jwtSecret,
      photos: PhotosConfig(maxBytes: 7, storage: storage),
    );

    test('carries photos across its JSON, as the config worker sends it', () {
      final read = AppConfig.fromJson(withStorage(s3).toJson());

      expect(read.photos.maxBytes, 7);
      expect(read.photos.storage, s3);
    });

    test('validate needs the S3 key pair in the environment', () {
      final config = withStorage(s3);

      expect(
        () => config.validate(environment: const {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('S3_ACCESS_KEY_ID'),
              contains('S3_SECRET_ACCESS_KEY'),
            ),
          ),
        ),
      );
      config.validate(
        environment: const {
          'S3_ACCESS_KEY_ID': 'id',
          'S3_SECRET_ACCESS_KEY': 'secret',
        },
      );
    });

    test('validate does not ask for S3 keys with local storage', () {
      withStorage(const LocalPhotoStorage()).validate(environment: const {});
    });

    test('validate rejects an endpoint that is not a URL', () {
      final config = withStorage(
        const S3PhotoStorage(endpoint: 'r2.example.com', bucket: 'b'),
      );

      expect(
        () => config.validate(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('photos.storage.endpoint'),
          ),
        ),
      );
    });
  });
}
