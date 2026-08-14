import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/utils/canonical_path.dart';

void main() {
  late io.Directory root;

  setUp(() {
    root = io.Directory.systemTemp.createTempSync('zonai_canonical_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  T scoped<T>(T Function() body) =>
      runScoped(body, values: {fsProvider.overrideWith(LocalFileSystem.new)});

  test('resolves a directory that exists', () {
    final real = root.resolveSymbolicLinksSync();

    expect(scoped(() => canonicalPath(root.path)), real);
  });

  test('follows a symlink to the directory it points at', () {
    final target = io.Directory(p.join(root.path, 'target'))..createSync();
    final link = io.Link(p.join(root.path, 'link'))..createSync(target.path);

    expect(
      scoped(() => canonicalPath(link.path)),
      target.resolveSymbolicLinksSync(),
    );
  });

  // The reason this is not just `resolveSymbolicLinksSync`: the paths that
  // most need one consistent spelling are the ones about to be created. The
  // `--config` path zonai hands raindrop_cli names a file that deliberately
  // never exists, and resolving only what happens to exist yet is exactly how
  // two paths to one directory drift into two different strings.
  test('resolves the deepest existing ancestor of a path that does not '
      'exist, and keeps the rest', () {
    final missing = p.join(root.path, 'not', 'there', 'yet.yaml');

    expect(
      scoped(() => canonicalPath(missing)),
      p.join(root.resolveSymbolicLinksSync(), 'not', 'there', 'yet.yaml'),
    );
  });

  test('a path under a symlinked parent still resolves the parent', () {
    final target = io.Directory(p.join(root.path, 'target'))..createSync();
    final link = io.Link(p.join(root.path, 'link'))..createSync(target.path);

    expect(
      scoped(() => canonicalPath(p.join(link.path, 'unwritten.sql'))),
      p.join(target.resolveSymbolicLinksSync(), 'unwritten.sql'),
    );
  });

  test('makes a relative path absolute', () {
    final result = scoped(() => canonicalPath('lib'));

    expect(p.isAbsolute(result), isTrue);
    expect(p.basename(result), 'lib');
  });

  test('is idempotent', () {
    final once = scoped(() => canonicalPath(root.path));

    expect(scoped(() => canonicalPath(once)), once);
  });
}
