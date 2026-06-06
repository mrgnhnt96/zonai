import 'dart:io';

import '../deps/clean_up.dart';
import '../deps/fs.dart';
import '../deps/logger.dart';
import '../deps/settings.dart';

/// Prevents two `zonai serve` processes from opening the same SQLite database.
class ServeLock {
  ServeLock._(this._lockFile, this._handle);

  final File _lockFile;
  final RandomAccessFile _handle;

  static File _lockPath() =>
      fs.file(fs.path.join(settings.dataPath, '.serve.lock'));

  /// Returns a lock when this process may start serving, or null if another
  /// live `zonai serve` already holds it.
  static ServeLock? tryAcquire() {
    final lockFile = _lockPath();
    lockFile.parent.createSync(recursive: true);

    try {
      final handle = lockFile.openSync(mode: FileMode.write);
      handle.lockSync(FileLock.exclusive);
      handle
        ..setPositionSync(0)
        ..writeStringSync('$pid\n')
        ..flushSync();

      final lock = ServeLock._(lockFile, handle);
      cleanUp.add(lock.release);
      return lock;
    } on FileSystemException {
      logger.info('Another zonai serve is already running');
      return null;
    }
  }

  void release() {
    try {
      _handle.closeSync();
    } catch (_) {
      // Process may already be tearing down.
    }

    if (_lockFile.existsSync()) {
      _lockFile.deleteSync();
    }
  }
}
