import 'dart:convert';

import 'package:test/test.dart';
import 'package:zonai/src/domain/photo_storage/bucket_photo_storage.dart';
import 'package:zonai/src/domain/photo_storage/s3_signer.dart';

import '../../../support/fake_s3_server.dart';

void main() {
  late FakeS3Server server;
  late BucketPhotoStorage storage;

  Future<void> start({int pageSize = 1000}) async {
    server = await FakeS3Server.start(pageSize: pageSize);
    storage = BucketPhotoStorage(
      endpoint: server.endpoint,
      bucket: server.bucket,
      region: FakeS3Server.region,
      credentials: FakeS3Server.credentials,
    );
  }

  setUp(start);
  tearDown(() => server.close());

  Future<List<int>> read(String key) =>
      storage.openRead(key).expand((chunk) => chunk).toList();

  test('writes and reads back an object with its content type', () async {
    await storage.write(
      'posts/a.jpg',
      Stream.fromIterable([
        [1, 2],
        [3],
      ]),
    );

    expect(await read('posts/a.jpg'), [1, 2, 3]);
    expect(server.objects['posts/a.jpg']!.contentType, 'image/jpeg');
  });

  test(
    'stat reports size and the bucket ETag, and null when missing',
    () async {
      await storage.write('posts/a.jpg', Stream.value([1, 2, 3]));

      final stored = await storage.stat('posts/a.jpg');
      expect(stored!.size, 3);
      expect(stored.etag, isNotNull);
      expect(stored.etag, isNot(contains('"')));
      expect(await storage.stat('posts/missing.jpg'), isNull);
      expect(await storage.exists('posts/a.jpg'), isTrue);
      expect(await storage.exists('posts/missing.jpg'), isFalse);
    },
  );

  test('the ETag changes when the bytes do, within the same second', () async {
    await storage.write('posts/a.jpg', Stream.value([1]));
    final before = await storage.stat('posts/a.jpg');
    await storage.write('posts/a.jpg', Stream.value([2]));
    final after = await storage.stat('posts/a.jpg');

    expect(after!.etag, isNot(before!.etag));
  });

  test('delete removes an object and ignores a missing one', () async {
    await storage.write('posts/a.jpg', Stream.value([1]));

    await storage.delete('posts/a.jpg');
    await storage.delete('posts/a.jpg');

    expect(server.objects, isEmpty);
  });

  test('rename copies then deletes the source', () async {
    await storage.write('posts/a.jpg.tmp', Stream.value([7]));

    await storage.rename('posts/a.jpg.tmp', 'posts/a.jpg');

    expect(server.objects.keys, ['posts/a.jpg']);
    expect(await read('posts/a.jpg'), [7]);
  });

  test('rename fails, keeping the source, when the copy fails', () async {
    await expectLater(
      storage.rename('posts/missing.jpg', 'posts/a.jpg'),
      throwsA(isA<BucketRequestException>()),
    );
    expect(server.requests.where((r) => r.startsWith('DELETE')), isEmpty);
  });

  test('list pages through every object and decodes escaped keys', () async {
    await server.close();
    await start(pageSize: 2);
    const keys = ['a/1.jpg', 'a/2.jpg', 'b/3&4.jpg', "b/it's.png", 'c/5.jpg'];
    for (final key in keys) {
      await storage.write(key, Stream.value(utf8.encode(key)));
    }

    final listed = await storage.list().toList();

    expect(listed.map((p) => p.key), unorderedEquals(keys));
    expect(
      server.requests.where((r) => r.contains('list-type=2')),
      hasLength(3),
    );
    final usage = await storage.usage();
    expect(usage.count, keys.length);
    expect(
      usage.bytes,
      keys.fold<int>(0, (sum, key) => sum + utf8.encode(key).length),
    );
  });

  test('a key with spaces and unicode round-trips signed', () async {
    await storage.write('posts/a b é.jpg', Stream.value([1]));

    expect(await read('posts/a b é.jpg'), [1]);
  });

  // A Windows host builds keys with `path.join`, and the `_photos.path` it
  // stores says `posts\<id>.jpg`. The bucket must still see `posts/<id>.jpg`.
  group('a key with backslashes', () {
    test('is stored and read under forward slashes', () async {
      await storage.write(r'posts\a.jpg', Stream.value([1]));

      expect(server.objects.keys, ['posts/a.jpg']);
      expect(await read(r'posts\a.jpg'), [1]);
      expect(await storage.exists(r'posts\a.jpg'), isTrue);
    });

    test('renames and deletes the same object', () async {
      await storage.write(r'posts\a.jpg.tmp', Stream.value([7]));

      await storage.rename(r'posts\a.jpg.tmp', r'posts\a.jpg');
      expect(server.objects.keys, ['posts/a.jpg']);

      await storage.delete(r'posts\a.jpg');
      expect(server.objects, isEmpty);
    });

    // What `_photoRedirect` puts after `publicBaseUrl`.
    test('encodes for a URL under forward slashes', () {
      expect(
        BucketPhotoStorage.encodeObjectKey(r'posts\a b.jpg'),
        'posts/a%20b.jpg',
      );
    });

    test('is presigned under forward slashes', () {
      final url = storage.presignedGetUrl(
        r'posts\a.jpg',
        expires: const Duration(minutes: 1),
      );

      expect(url.path, '/${server.bucket}/posts/a.jpg');
    });
  });

  test('a wrongly signed request is refused, not silently accepted', () async {
    final wrong = BucketPhotoStorage(
      endpoint: server.endpoint,
      bucket: server.bucket,
      region: FakeS3Server.region,
      credentials: const S3Credentials(
        accessKeyId: 'test-access-key',
        secretAccessKey: 'not-the-secret',
      ),
    );

    await expectLater(
      wrong.write('posts/a.jpg', Stream.value([1])),
      throwsA(
        isA<BucketRequestException>().having(
          (e) => e.statusCode,
          'status',
          403,
        ),
      ),
    );
    await expectLater(
      read('posts/missing.jpg'),
      throwsA(
        isA<BucketRequestException>().having(
          (e) => e.statusCode,
          'status',
          404,
        ),
      ),
    );
  });
}
