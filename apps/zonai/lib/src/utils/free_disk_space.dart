import 'dart:io' show Platform;

import '../deps/process.dart';

/// Bytes available to a non-privileged writer on the volume holding [path],
/// or `null` when it cannot be determined.
///
/// Dart exposes no API for this, so it shells out. That is affordable here
/// because the only caller runs once per nightly cron, and it is worth paying
/// at all because the alternative — attempting the rewrite and finding out —
/// means filling the last of a nearly-full volume to learn it was nearly
/// full, taking every other writer down with it for the duration.
///
/// **`null` means unknown, never zero.** Callers must not read it as "no
/// space": an unparsed `df` and a full disk are opposite situations, and
/// treating them alike would refuse to reclaim space on every platform this
/// does not recognise.
Future<int?> freeDiskBytes(String path) async {
  try {
    if (Platform.isWindows) {
      // `(Get-PSDrive X).Free` prints a bare integer. Chosen over `fsutil
      // volume diskfree`, whose output is prose and localised, and over
      // `wmic`, which recent Windows no longer ships.
      final drive = _windowsDriveLetter(path);
      if (drive == null) return null;
      final result = await process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '(Get-PSDrive $drive).Free',
      ]);
      if (result.exitCode != 0) return null;
      return int.tryParse('${result.stdout}'.trim());
    }

    // `-P` is what makes this parseable: POSIX output format guarantees one
    // line per filesystem, where the default wraps a long device name onto a
    // second line and shifts every column. `-k` fixes the block size at 1024
    // rather than letting BLOCKSIZE/`df` defaults decide it.
    final result = await process.run('df', ['-Pk', path]);
    if (result.exitCode != 0) return null;
    return parseDfAvailableBytes('${result.stdout}');
  } catch (_) {
    // A missing `df`, a sandbox that refuses to spawn, an unreadable path:
    // all of them mean "unknown", which is what this returns for everything
    // it cannot answer.
    return null;
  }
}

/// Available bytes from `df -Pk` output, or `null` if it does not parse.
///
/// Separated from the call so the parsing — the part that actually breaks —
/// can be tested against real captured output without spawning anything.
int? parseDfAvailableBytes(String stdout) {
  final lines = stdout
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  // Header, then one line for the filesystem holding the path.
  if (lines.length < 2) return null;

  final columns = lines.last.split(RegExp(r'\s+'));
  // Filesystem, 1024-blocks, Used, Available, Capacity, Mounted on — and
  // "Mounted on" may itself contain spaces, so this checks a floor, not an
  // exact count.
  if (columns.length < 5) return null;

  final blocks = int.tryParse(columns[3]);
  if (blocks == null) return null;
  return blocks * 1024;
}

/// The drive letter [path] sits on (`C`), or `null` for a UNC or relative
/// path where there is no letter to ask about.
String? _windowsDriveLetter(String path) {
  if (path.length < 2 || path[1] != ':') return null;
  final letter = path[0].toUpperCase();
  if (letter.codeUnitAt(0) < 0x41 || letter.codeUnitAt(0) > 0x5A) return null;
  return letter;
}
