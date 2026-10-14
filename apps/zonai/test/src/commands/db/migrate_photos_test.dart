import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/db/migrate_photos.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/domain/photo_storage/bucket_photo_storage.dart';
import 'package:zonai/src/domain/photo_storage/disk_photo_storage.dart';
import 'package:zonai/src/domain/photo_storage/s3_signer.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../../../support/fake_s3_server.dart';
import 'admin/fake_zonai_db.dart';

class _CapturingSink implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.forEach(bytes.addAll);
  }

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}

void main() {
  late FakeS3Server server;
  late MemoryFileSystem memoryFs;
  late FakeZonaiDb db;

  setUp(() async {
    server = await FakeS3Server.start();
    memoryFs = MemoryFileSystem();
    db = newFakeZonaiDb()
      ..photoStorage = BucketPhotoStorage(
        endpoint: server.endpoint,
        bucket: server.bucket,
        region: FakeS3Server.region,
        credentials: FakeS3Server.credentials,
      );
  });
  tearDown(() => server.close());

  void onDisk(String key, List<int> bytes) =>
      memoryFs.file(memoryFs.path.join(fakeSettings.imagesPath, key))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

  bool diskHas(String key) => memoryFs
      .file(memoryFs.path.join(fakeSettings.imagesPath, key))
      .existsSync();

  Future<({int exitCode, String output})> run(Map<String, Object?> args) async {
    final sink = _CapturingSink();
    final exitCode = await runScoped(
      migratePhotos,
      values: {
        argsProvider.overrideWith(() => Args(args: args)),
        loggerProvider.overrideWith(
          () =>
              Logger(level: .info, stdout: IOSink(sink), stderr: IOSink(sink)),
        ),
        settingsProvider.overrideWith(() => fakeSettings),
        fsProvider.overrideWith(() => memoryFs),
        zonaiDbProvider.overrideWith(
          () =>
              () => db,
        ),
      },
    );
    return (exitCode: exitCode, output: sink.text);
  }

  test('prints usage for --help and copies nothing', () async {
    onDisk('posts/a.jpg', [1]);

    final result = await run({'help': true});

    expect(result.exitCode, 1);
    expect(result.output, contains('zonai db migrate-photos'));
    expect(server.objects, isEmpty);
  });

  test('refuses when storage is local', () async {
    db.photoStorage = DiskPhotoStorage(fs: memoryFs, root: '/elsewhere');

    final result = await run({});

    expect(result.exitCode, 1);
    expect(result.output, contains('PhotosConfig.storage is local'));
  });

  test('copies each photo with progress and keeps local files', () async {
    onDisk('posts/a.jpg', [1, 2, 3]);
    onDisk('posts/b.jpg', [4]);
    onDisk('favicon.ico', [9]);

    final result = await run({});

    expect(result.exitCode, 0);
    expect(
      server.objects.keys,
      unorderedEquals(['posts/a.jpg', 'posts/b.jpg']),
    );
    expect(result.output, contains('[1/2] posts/a.jpg (3 B) copied'));
    expect(result.output, contains('[2/2] posts/b.jpg (1 B) copied'));
    expect(result.output, contains('Copied 2 (4 B), 0 already in bucket'));
    expect(diskHas('posts/a.jpg'), isTrue);

    final again = await run({});
    expect(again.output, contains('[1/2] posts/a.jpg (3 B) already in bucket'));
    expect(again.output, contains('Copied 0 (0 B), 2 already in bucket'));
  });

  test('--dry-run lists and changes nothing', () async {
    onDisk('posts/a.jpg', [1, 2, 3]);

    final result = await run({'dry-run': true, 'delete-local': true});

    expect(result.exitCode, 0);
    expect(result.output, contains('[1/1] posts/a.jpg (3 B) would copy'));
    expect(result.output, contains('Would copy 1 (3 B)'));
    expect(server.objects, isEmpty);
    expect(diskHas('posts/a.jpg'), isTrue);
  });

  test('--delete-local deletes each verified photo', () async {
    onDisk('posts/a.jpg', [1, 2, 3]);

    final result = await run({'delete-local': true});

    expect(result.exitCode, 0);
    expect(result.output, contains('copied, local file deleted'));
    expect(result.output, contains('1 local deleted'));
    expect(diskHas('posts/a.jpg'), isFalse);
    expect(server.objects['posts/a.jpg']!.bytes, Uint8List.fromList([1, 2, 3]));
  });

  test('exits 1 and says to re-run when a photo fails', () async {
    onDisk('posts/a.jpg', [1]);
    db.photoStorage = BucketPhotoStorage(
      endpoint: server.endpoint,
      bucket: server.bucket,
      region: FakeS3Server.region,
      // The fake server refuses a request signed with any other key.
      credentials: const S3Credentials(
        accessKeyId: 'wrong',
        secretAccessKey: 'wrong',
      ),
    );

    final result = await run({});

    expect(result.exitCode, 1);
    expect(result.output, contains('[1/1] posts/a.jpg (1 B) FAILED'));
    expect(result.output, contains('Run the command again to retry'));
    expect(diskHas('posts/a.jpg'), isTrue);
  });
}
