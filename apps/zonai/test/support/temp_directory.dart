import 'dart:io';

/// A fresh temp directory named the way the FILESYSTEM spells it.
///
/// `Directory.systemTemp.createTempSync` hands back whatever spelling `TEMP`
/// is set to, and on a GitHub Windows runner that is the 8.3 short name
/// `C:\Users\RUNNER~1\...` for a directory whose real name is
/// `C:\Users\runneradmin\...`. macOS has the same hazard in a different
/// costume: `/var/folders/...` is a symlink to `/private/var/folders/...`.
///
/// It matters because code downstream decides "is this file inside that
/// package" with a string comparison. raindrop_cli's
/// `SnapshotRunner.packageUri` does exactly that, and answers no for a schema
/// that IS under `lib/` when the two sides are spelled differently:
///
///     Bad state: Schema file "C:\Users\runneradmin\...\lib\src\schemas\admins.dart"
///     is not inside a package's lib/ directory, so it cannot be imported.
///
/// That failed six e2e suites in `cli (windows-latest)` on run 31850921551,
/// all in `setUpAll`, after the same class of bug had already been fixed once
/// for `--config`/`--schemas` in migrate.dart. The production side of it lives
/// in `canonicalPath`; this is the test-harness side, and it is separate
/// because these suites use `dart:io` directly rather than the injected
/// filesystem.
///
/// `resolveSymbolicLinksSync` rather than `canonicalPath` because the
/// directory has just been created and therefore exists — the ancestor-walking
/// that `canonicalPath` does is only needed for a path that does not.
Directory createCanonicalTempSync(String prefix) {
  final created = Directory.systemTemp.createTempSync(prefix);
  return Directory(created.resolveSymbolicLinksSync());
}

/// Deletes [file], waiting out a Windows handle that is about to close.
///
/// Windows refuses to unlink a file any process still has open, and a loaded
/// DLL is open by definition. A test that spawns a worker, lets it load
/// `resqlite.dll`, and then deletes that DLL to prove the worker re-requests
/// it, races the worker's exit:
///
///     PathAccessException: Cannot delete file, path =
///       'D:\a\zonai\zonai\apps\zonai\.dart_tool\lib\resqlite.dll'
///       (OS Error: Access is denied, errno = 5)
///
/// Two tests in `cli (windows-latest)` failed exactly that way on run
/// 31852302306.
///
/// Unlike [deleteTempDirectory] this does NOT give up quietly on Windows. The
/// deletion is the PREMISE of those tests -- if the library is still there,
/// the worker has no reason to request it and a pass would mean nothing. So a
/// lock that outlives the retries is a real failure and is allowed to throw.
void deleteFileWithRetry(File file) {
  if (!file.existsSync()) return;

  for (var attempt = 0; ; attempt++) {
    try {
      file.deleteSync();
      return;
    } on FileSystemException {
      if (!Platform.isWindows || attempt >= 9) rethrow;
      sleep(const Duration(milliseconds: 200));
    }
  }
}

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
