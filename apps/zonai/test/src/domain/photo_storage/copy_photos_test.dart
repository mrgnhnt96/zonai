import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:zonai/src/domain/photo_storage/bucket_photo_storage.dart';
import 'package:zonai/src/domain/photo_storage/copy_photos.dart';
import 'package:zonai/src/domain/photo_storage/disk_photo_storage.dart';
import 'package:zonai/src/domain/photo_storage/photo_storage.dart';

import '../../../support/fake_s3_server.dart';

const _root = '/app/.zonai/data/images';

void main() {
  late FakeS3Server server;
  late BucketPhotoStorage bucket;
  late MemoryFileSystem fs;
  late DiskPhotoStorage disk;

  setUp(() async {
    server = await FakeS3Server.start();
    bucket = BucketPhotoStorage(
      endpoint: server.endpoint,
      bucket: server.bucket,
      region: FakeS3Server.region,
      credentials: FakeS3Server.credentials,
    );
    fs = MemoryFileSystem();
    disk = DiskPhotoStorage(fs: fs, root: _root);
  });
  tearDown(() => server.close());

  void onDisk(String key, List<int> bytes) => fs.file('$_root/$key')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  void inBucket(String key, List<int> bytes) => server.objects[key] = (
    bytes: Uint8List.fromList(bytes),
    contentType: 'image/jpeg',
    modified: DateTime.now().toUtc(),
  );

  bool diskHas(String key) => fs.file('$_root/$key').existsSync();

  group('isPhotoKey', () {
    test('accepts <table>/<id>.<image ext> only', () {
      expect(isPhotoKey('posts/a_ph.jpg'), isTrue);
      expect(isPhotoKey('posts/a_ph.PNG'), isTrue);
      expect(isPhotoKey('favicon.ico'), isFalse);
      expect(isPhotoKey('logo.png'), isFalse);
      expect(isPhotoKey('posts/a_ph.jpg.tmp'), isFalse);
      expect(isPhotoKey('posts/notes.txt'), isFalse);
      expect(isPhotoKey('posts/noext'), isFalse);
    });
  });

  test('copies every photo and leaves brand assets and local files', () async {
    onDisk('posts/a.jpg', [1, 2, 3]);
    onDisk('users/b.png', [4, 5]);
    onDisk('favicon.ico', [9]);
    onDisk('logo.png', [9]);
    onDisk('posts/a.jpg.tmp', [9]);

    final progress = <PhotoCopyProgress>[];
    final summary = await copyPhotos(
      source: disk,
      target: bucket,
      onProgress: progress.add,
    );

    expect(
      server.objects.keys,
      unorderedEquals(['posts/a.jpg', 'users/b.png']),
    );
    expect(server.objects['posts/a.jpg']!.bytes, [1, 2, 3]);
    expect(server.objects['users/b.png']!.contentType, 'image/png');
    expect(summary.copied, 2);
    expect(summary.bytes, 5);
    expect(summary.failed, 0);
    expect(
      [for (final p in progress) '${p.index}/${p.total} ${p.photo.key}'],
      ['1/2 posts/a.jpg', '2/2 users/b.png'],
    );
    expect(diskHas('posts/a.jpg'), isTrue);
    expect(diskHas('users/b.png'), isTrue);
  });

  test('a second run sends nothing', () async {
    onDisk('posts/a.jpg', [1, 2, 3]);
    await copyPhotos(source: disk, target: bucket);
    server.requests.clear();

    final summary = await copyPhotos(source: disk, target: bucket);

    expect(summary.alreadyThere, 1);
    expect(summary.copied, 0);
    expect(server.requests.where((r) => r.startsWith('PUT')), isEmpty);
  });

  test('resumes: only photos missing or a different size are sent', () async {
    onDisk('posts/a.jpg', [1, 2, 3]);
    onDisk('posts/b.jpg', [1, 2, 3]);
    onDisk('posts/c.jpg', [1, 2, 3]);
    inBucket('posts/a.jpg', [1, 2, 3]);
    // A partial upload from an interrupted run.
    inBucket('posts/b.jpg', [1]);

    final summary = await copyPhotos(source: disk, target: bucket);

    expect(summary.alreadyThere, 1);
    expect(summary.copied, 2);
    expect(server.objects['posts/b.jpg']!.bytes, [1, 2, 3]);
    expect(server.requests.where((r) => r.startsWith('PUT')), [
      'PUT /photos/posts/b.jpg',
      'PUT /photos/posts/c.jpg',
    ]);
  });

  test('a dry run reports and changes nothing', () async {
    onDisk('posts/a.jpg', [1, 2, 3]);
    onDisk('posts/b.jpg', [1]);
    inBucket('posts/b.jpg', [1]);

    final summary = await copyPhotos(
      source: disk,
      target: bucket,
      dryRun: true,
      deleteSource: true,
    );

    expect(summary.wouldCopy, 1);
    expect(summary.alreadyThere, 1);
    expect(summary.bytes, 3);
    expect(server.objects.keys, ['posts/b.jpg']);
    expect(diskHas('posts/a.jpg'), isTrue);
    expect(diskHas('posts/b.jpg'), isTrue);
  });

  test(
    'deleteSource deletes each local photo once the bucket has it',
    () async {
      onDisk('posts/a.jpg', [1, 2, 3]);
      onDisk('posts/b.jpg', [1]);
      inBucket('posts/b.jpg', [1]);
      onDisk('favicon.ico', [9]);

      final summary = await copyPhotos(
        source: disk,
        target: bucket,
        deleteSource: true,
      );

      expect(summary.deleted, 2);
      expect(diskHas('posts/a.jpg'), isFalse);
      expect(diskHas('posts/b.jpg'), isFalse);
      expect(diskHas('favicon.ico'), isTrue);
      expect(
        server.objects.keys,
        unorderedEquals(['posts/a.jpg', 'posts/b.jpg']),
      );
    },
  );

  test('a size mismatch after upload fails that photo and keeps the local '
      'file, and the rest carry on', () async {
    onDisk('posts/a.jpg', [1, 2, 3]);
    onDisk('posts/b.jpg', [4, 5]);

    final progress = <PhotoCopyProgress>[];
    final summary = await copyPhotos(
      source: disk,
      target: _Truncating(bucket, key: 'posts/a.jpg'),
      deleteSource: true,
      onProgress: progress.add,
    );

    expect(summary.failed, 1);
    expect(summary.copied, 1);
    expect(progress.first.outcome, PhotoCopyOutcome.failed);
    expect(
      progress.first.error,
      isA<PhotoCopySizeMismatch>()
          .having((e) => e.expected, 'expected', 3)
          .having((e) => e.actual, 'actual', 2),
    );
    expect(diskHas('posts/a.jpg'), isTrue);
    expect(diskHas('posts/b.jpg'), isFalse);
  });

  test('a refused upload fails that photo and the rest carry on', () async {
    onDisk('posts/a.jpg', [1]);
    onDisk('posts/b.jpg', [2]);
    final wrongKeys = BucketPhotoStorage(
      endpoint: server.endpoint,
      bucket: 'other',
      region: FakeS3Server.region,
      credentials: FakeS3Server.credentials,
    );

    final summary = await copyPhotos(source: disk, target: wrongKeys);

    expect(summary.failed, 2);
    expect(diskHas('posts/a.jpg'), isTrue);
  });

  test('a missing images directory copies nothing', () async {
    final summary = await copyPhotos(source: disk, target: bucket);

    expect(summary.copied + summary.failed + summary.alreadyThere, 0);
  });
}

/// Stores one fewer byte than it was sent for [key].
final class _Truncating extends PhotoStorage {
  _Truncating(this._inner, {required this.key});

  final PhotoStorage _inner;
  final String key;

  @override
  Future<void> write(String key, Stream<List<int>> bytes) async {
    if (key != this.key) return _inner.write(key, bytes);
    final all = await bytes.expand((chunk) => chunk).toList();
    await _inner.write(key, Stream.value(all.sublist(0, all.length - 1)));
  }

  @override
  Stream<List<int>> openRead(String key) => _inner.openRead(key);

  @override
  Future<StoredPhoto?> stat(String key) => _inner.stat(key);

  @override
  Future<bool> exists(String key) => _inner.exists(key);

  @override
  Future<void> delete(String key) => _inner.delete(key);

  @override
  Future<void> rename(String from, String to) => _inner.rename(from, to);

  @override
  Stream<StoredPhoto> list() => _inner.list();
}
