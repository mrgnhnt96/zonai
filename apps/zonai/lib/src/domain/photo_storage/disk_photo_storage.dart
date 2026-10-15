import 'package:file/file.dart';
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:zonai/src/domain/photo_storage/photo_storage.dart';
import 'package:zonai/src/exceptions/photo_exception.dart';

/// Photos as files under [root], the project's images directory.
///
/// Every key is resolved through [resolvePhotoFile], so a key that would land
/// outside [root] throws [InvalidPhotoPathException] instead of touching the
/// disk.
final class DiskPhotoStorage extends PhotoStorage {
  const DiskPhotoStorage({required this.fs, required this.root});

  final FileSystem fs;
  final String root;

  File _file(String key) => resolvePhotoFile(fs, root, key);

  @override
  Future<void> write(String key, Stream<List<int>> bytes) async {
    final file = _file(key);
    await file.parent.create(recursive: true);

    // The sink MUST be closed, not just awaited. `addStream` completes when
    // the stream is drained and leaves the sink -- and the OS file handle --
    // open. POSIX renames a file with an open handle without complaint, so
    // the leak read as correct on macOS and Linux. Windows refuses, and the
    // exception surfaced as `[500] PATCH /img/:id` for the owner, because
    // updating a photo renames the file it just wrote. Found by e2e (windows)
    // on run 31855231392.
    final sink = file.openWrite();
    try {
      await sink.addStream(bytes);
    } finally {
      await sink.close();
    }
  }

  @override
  Stream<List<int>> openRead(String key) => _file(key).openRead();

  @override
  Future<StoredPhoto?> stat(String key) async {
    final file = _file(key);
    if (!file.existsSync()) return null;

    final stat = file.statSync();
    return StoredPhoto(key: key, size: stat.size, modified: stat.modified);
  }

  @override
  Future<bool> exists(String key) async => _file(key).existsSync();

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    final target = _file(to);
    await _file(from).rename(target.path);
  }

  /// Every file under [root], walked recursively without following links.
  ///
  /// That includes the favicon and logo when a project keeps them in the
  /// images directory, which is what the storage report has always counted.
  ///
  /// A missing [root] lists nothing rather than failing: a deployment that has
  /// never accepted a photo has no images directory, and that is not a fault.
  @override
  Stream<StoredPhoto> list() async* {
    final dir = fs.directory(root);
    if (!dir.existsSync()) return;

    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;

      final FileStat stat;
      try {
        stat = entity.statSync();
      } catch (_) {
        // A file this process cannot read. Skipping it under-reports by one
        // file, which is the right direction for a listing that must not
        // throw.
        continue;
      }
      // A file that vanished between the listing and the stat.
      if (stat.type == FileSystemEntityType.notFound) continue;

      yield StoredPhoto(
        key: fs.path.relative(entity.path, from: root),
        size: stat.size,
        modified: stat.modified,
      );
    }
  }
}

/// Resolves [relativePath] against [imagesPath] and refuses anything that
/// lands outside it.
///
/// The check this replaces read
/// `if (fs.path.isWithin(settings.imagesPath, relativePath)) throw ...`, which
/// was wrong twice over and therefore dead:
///
///   * `relativePath` is RELATIVE (`posts/<id>.jpg`) and `imagesPath` is the
///     resolved images root, so `isWithin` was comparing a relative path
///     against an absolute one — `false` for every input this code can
///     produce, traversal included. Measured, not reasoned: with
///     `imagesPath = /srv/app/.zonai/data/images`, `isWithin` answers `false`
///     for `posts/x.jpg`, for `../escape.jpg` and for `../../../etc/passwd`
///     alike.
///   * the sense was inverted. Had the arguments been right it would have
///     thrown on the legitimate case and admitted the escape.
///
/// Containment is a property of the RESOLVED path, so that is what gets
/// checked. Both sides go through the same `absolute`/`normalize` pair because
/// `imagesPath` is only absolute when a `zonai.yaml` was found — `isWithin`
/// with one relative side is the bug above all over again.
///
/// This does NOT follow symlinks: a symlink inside the images root pointing
/// out of it still resolves as contained. The paths this guards are generated
/// by `_createPhoto` from a registered table name and a fresh id, so the
/// escape it defends against is a hostile `table`, not a planted link.
@visibleForTesting
File resolvePhotoFile(FileSystem fs, String imagesPath, String relativePath) {
  final file = fs.file(fs.path.join(imagesPath, relativePath));

  final root = fs.path.normalize(fs.path.absolute(imagesPath));
  final resolved = fs.path.normalize(fs.path.absolute(file.path));

  if (!fs.path.isWithin(root, resolved)) {
    throw InvalidPhotoPathException(path: relativePath);
  }

  return file;
}
