import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:zonai/src/domain/photo_storage/disk_photo_storage.dart';
import 'package:zonai/src/domain/photo_storage/photo_storage.dart';
import 'package:zonai/src/exceptions/photo_exception.dart';

/// [PhotoStorage]'s contract, held by the local-disk backend.
///
/// Written against the interface, so the same cases describe what any other
/// backend has to do. Only the containment group and the paths checked on
/// the memory file system are specific to files.
void main() {
  const root = '/srv/app/.zonai/data/images';

  late MemoryFileSystem fs;
  late PhotoStorage storage;

  setUp(() {
    fs = MemoryFileSystem();
    storage = DiskPhotoStorage(fs: fs, root: root);
  });

  Future<List<int>> read(String key) =>
      storage.openRead(key).expand((chunk) => chunk).toList();

  group('write', () {
    test('stores the bytes under the key, creating parents', () async {
      await storage.write('posts/a.jpg', Stream.value([1, 2, 3]));

      expect(await read('posts/a.jpg'), [1, 2, 3]);
      expect(fs.file('$root/posts/a.jpg').existsSync(), isTrue);
    });

    test('joins every chunk of the stream', () async {
      await storage.write(
        'a.jpg',
        Stream.fromIterable([
          [1],
          [2, 3],
          [4],
        ]),
      );

      expect(await read('a.jpg'), [1, 2, 3, 4]);
    });

    test('replaces what was there', () async {
      await storage.write('a.jpg', Stream.value([1, 2, 3]));
      await storage.write('a.jpg', Stream.value([9]));

      expect(await read('a.jpg'), [9]);
    });

    test('rethrows an error from the stream', () async {
      final bytes = Stream<List<int>>.multi((controller) {
        controller
          ..add([1])
          ..addError(StateError('too big'))
          ..close();
      });

      await expectLater(storage.write('a.jpg', bytes), throwsStateError);
      // The write is closed, so the partial file can be cleaned up.
      await storage.delete('a.jpg');
      expect(await storage.exists('a.jpg'), isFalse);
    });
  });

  group('stat', () {
    test('is null when nothing is stored', () async {
      expect(await storage.stat('missing.jpg'), isNull);
    });

    test('reports the key, size and modification time', () async {
      await storage.write('posts/a.jpg', Stream.value([1, 2, 3, 4]));

      final stat = await storage.stat('posts/a.jpg');

      expect(stat?.key, 'posts/a.jpg');
      expect(stat?.size, 4);
      expect(stat?.modified, fs.file('$root/posts/a.jpg').statSync().modified);
    });
  });

  group('exists', () {
    test('is false before a write and true after', () async {
      expect(await storage.exists('a.jpg'), isFalse);

      await storage.write('a.jpg', Stream.value([1]));

      expect(await storage.exists('a.jpg'), isTrue);
    });
  });

  group('delete', () {
    test('removes what is stored', () async {
      await storage.write('a.jpg', Stream.value([1]));

      await storage.delete('a.jpg');

      expect(await storage.exists('a.jpg'), isFalse);
    });

    test('does nothing when nothing is stored', () async {
      await storage.delete('missing.jpg');

      expect(await storage.exists('missing.jpg'), isFalse);
    });
  });

  group('rename', () {
    test('moves the bytes to the new key', () async {
      await storage.write('posts/a.jpg.tmp', Stream.value([1, 2]));

      await storage.rename('posts/a.jpg.tmp', 'posts/a.png');

      expect(await storage.exists('posts/a.jpg.tmp'), isFalse);
      expect(await read('posts/a.png'), [1, 2]);
    });

    test('replaces what is at the new key', () async {
      await storage.write('a.jpg', Stream.value([1]));
      await storage.write('a.jpg.tmp', Stream.value([2]));

      await storage.rename('a.jpg.tmp', 'a.jpg');

      expect(await read('a.jpg'), [2]);
    });
  });

  group('list', () {
    test('is empty when the root does not exist', () async {
      expect(await storage.list().toList(), isEmpty);
    });

    test('lists every key under the root, nested ones included', () async {
      await storage.write('a.jpg', Stream.value([1]));
      await storage.write('posts/b.png', Stream.value([1, 2]));
      await storage.write('posts/deep/c.webp', Stream.value([1, 2, 3]));

      final listed = {
        for (final photo in await storage.list().toList())
          photo.key: photo.size,
      };

      expect(listed, {
        'a.jpg': 1,
        fs.path.join('posts', 'b.png'): 2,
        fs.path.join('posts', 'deep', 'c.webp'): 3,
      });
    });

    test('skips directories', () async {
      fs.directory('$root/empty').createSync(recursive: true);

      expect(await storage.list().toList(), isEmpty);
    });
  });

  group('usage', () {
    test('is zero when nothing is stored', () async {
      expect(await storage.usage(), (bytes: 0, count: 0));
    });

    test('totals the bytes and entries of the listing', () async {
      await storage.write('a.jpg', Stream.value([1, 2, 3]));
      await storage.write('posts/b.png', Stream.value([1, 2, 3, 4, 5]));

      expect(await storage.usage(), (bytes: 8, count: 2));
    });
  });

  group('a key outside the root', () {
    const escape = '../escape.jpg';
    const outside = '/srv/app/.zonai/data/escape.jpg';

    setUp(() {
      fs.file(outside)
        ..createSync(recursive: true)
        ..writeAsBytesSync([7]);
    });

    final throwsInvalidPath = throwsA(isA<InvalidPhotoPathException>());

    test('is refused by write', () async {
      await expectLater(
        storage.write(escape, Stream.value([1])),
        throwsInvalidPath,
      );
      expect(fs.file(outside).readAsBytesSync(), [7]);
    });

    test('is refused by openRead', () {
      expect(() => storage.openRead(escape), throwsInvalidPath);
    });

    test('is refused by stat and exists', () async {
      await expectLater(storage.stat(escape), throwsInvalidPath);
      await expectLater(storage.exists(escape), throwsInvalidPath);
    });

    test('is refused by delete', () async {
      await expectLater(storage.delete(escape), throwsInvalidPath);
      expect(fs.file(outside).existsSync(), isTrue);
    });

    test('is refused by rename, on either side', () async {
      await storage.write('a.jpg', Stream.value([1]));

      await expectLater(storage.rename('a.jpg', escape), throwsInvalidPath);
      await expectLater(storage.rename(escape, 'a.jpg'), throwsInvalidPath);
      expect(fs.file(outside).readAsBytesSync(), [7]);
      expect(await read('a.jpg'), [1]);
    });
  });
}
