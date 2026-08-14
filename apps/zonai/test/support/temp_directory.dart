import 'dart:io';

/// Removes [directory] and everything under it, at the end of a test.
///
/// Plain `deleteSync(recursive: true)` is enough on macOS and Linux, where
/// unlinking a file another process still has open is legal. Windows refuses:
/// a directory cannot be removed while any handle into it is open, and a
/// handle outlives the process that held it by a moment. Tests that spawn a
/// compiled worker into their temp directory therefore fail in teardown after
/// every one of their assertions has passed:
///
///     PathAccessException: Deletion failed, path = 'C:\...\zonai_cron_jwt_auth_bf69f5f4'
///     (OS Error: Access is denied, errno = 5)
///
/// Three tests in `cli (windows-latest)` failed exactly that way. A short
/// retry covers the handle that is about to close. If it still will not go,
/// this gives up **on Windows only** — the directory is under the system temp
/// directory and the OS reclaims it, and failing a test over it would be
/// reporting on Windows' file locking rather than on zonai. On a POSIX host
/// the same failure means something genuinely wrong (a permission, a
/// read-only mount), so there it still throws.
void deleteTempDirectory(Directory directory) {
  if (!directory.existsSync()) return;

  for (var attempt = 0; ; attempt++) {
    try {
      directory.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (!Platform.isWindows) rethrow;
      if (attempt >= 4) return;
      sleep(const Duration(milliseconds: 200));
    }
  }
}
