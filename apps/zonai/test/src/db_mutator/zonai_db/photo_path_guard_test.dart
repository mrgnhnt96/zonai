import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/exceptions/photo_exception.dart';

/// `_createPhoto` built its on-disk path from a CALLER-SUPPLIED table name and
/// then "checked" containment with
///
///     if (fs.path.isWithin(settings.imagesPath, relativePath)) throw ...
///
/// which never fired. `relativePath` is relative and `imagesPath` is resolved,
/// so `isWithin` answered `false` for every input the code can produce -- and
/// the sense was inverted on top of that, so a correct answer would have
/// thrown on the legitimate case instead. The only thing standing between a
/// `meta.table` of `../../..` and a write outside the images root was
/// `_requireRegisteredTable`, which exists to look up photo columns rather
/// than to contain paths.
///
/// These tests pin the guard by its OUTCOME on the resolved path, so a future
/// rewrite that reintroduces an argument-order or sense mistake fails here
/// rather than passing quietly: the escape cases assert a throw, and the
/// legitimate case asserts one does NOT happen (a guard that always fires is
/// the other half of the same bug, and is what the inverted version would
/// have been).
void main() {
  late MemoryFileSystem fs;

  setUp(() => fs = MemoryFileSystem());

  const imagesRoot = '/srv/app/.zonai/data/images';

  test('a legitimate table-scoped path resolves inside the images root', () {
    final file = resolvePhotoFile(fs, imagesRoot, 'posts/abc123ph.jpg');

    expect(file.path, '$imagesRoot/posts/abc123ph.jpg');
  });

  test('a nested table-scoped path is still contained', () {
    final file = resolvePhotoFile(fs, imagesRoot, 'a/b/c/abc123ph.png');

    expect(file.path, '$imagesRoot/a/b/c/abc123ph.png');
  });

  for (final escape in const [
    '../escape.jpg',
    '../../../../etc/passwd',
    '../../data/db.sqlite',
    'posts/../../../escape.jpg',
  ]) {
    test('"$escape" escapes the images root and is refused', () {
      expect(
        () => resolvePhotoFile(fs, imagesRoot, escape),
        throwsA(isA<InvalidPhotoPathException>()),
      );
    });
  }

  test('an absolute path is refused rather than silently winning the join', () {
    // `p.join(root, '/etc/passwd')` discards `root` entirely -- the escape
    // needs no `..` at all.
    expect(
      () => resolvePhotoFile(fs, imagesRoot, '/etc/passwd'),
      throwsA(isA<InvalidPhotoPathException>()),
    );
  });

  test('the images root itself is not a valid photo path', () {
    expect(
      () => resolvePhotoFile(fs, imagesRoot, '.'),
      throwsA(isA<InvalidPhotoPathException>()),
    );
  });

  test(
    'containment holds when imagesPath is relative -- both sides are resolved '
    'the same way, which is exactly what the old check failed to do',
    () {
      fs.currentDirectory = fs.directory('/work')..createSync(recursive: true);

      expect(
        resolvePhotoFile(fs, '.zonai/data/images', 'posts/abc123ph.jpg').path,
        '.zonai/data/images/posts/abc123ph.jpg',
      );
      expect(
        () => resolvePhotoFile(fs, '.zonai/data/images', '../../../escape.jpg'),
        throwsA(isA<InvalidPhotoPathException>()),
      );
    },
  );
}
