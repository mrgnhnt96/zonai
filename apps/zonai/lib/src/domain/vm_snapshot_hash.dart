import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file/file.dart';

import '../deps/fs.dart';

/// The one way to obtain a Dart VM snapshot hash, and the one place that knows
/// what one looks like.
///
/// A zonai host binary and the `.aot` worker snapshots it loads through
/// `Isolate.spawnUri` (see mailman.dart) must come from Dart SDKs that share a
/// VM snapshot hash. Nothing today ties the two together: CI pins `sdk:
/// "3.12.0"` across its workflow jobs, so a released binary embeds a 3.12.0
/// runtime, while the snapshots are compiled by whatever SDK
/// `DartExecutable.resolve()` happens to find on the developer's machine.
///
/// ## Why the hash, and not a version
///
/// Compatibility follows the hash, not semver. Measured on macos-arm64:
/// 3.12.1 and 3.12.2 share `ace654289f5abc240509fc941453ebc5` and spawn each
/// other's snapshots in both directions; 3.12.0 is
/// `41be3daaabd524b8aa7423bc24584957` and does not, despite sharing a minor
/// with them. 3.13.1 and 3.13.2 again share one hash. Hash equality predicted
/// all eight measured spawn outcomes, so a semver range would be wrong in both
/// directions -- it would reject compatible pairs and accept incompatible
/// ones. A version *string* is carried alongside the hash for message text
/// only ("requires Dart 3.12.0, you are on 3.13.2"); it is never compared.
///
/// ## Why this is worth a guard at all
///
/// Two failure modes, and only one of them is survivable. Same container
/// format with a different hash raises `IsolateSpawnException: Wrong full
/// snapshot version`, which mailman's existing `try`/`catch` handles. Across a
/// container-format change -- a 3.12.x host loading a 3.13.x snapshot -- the
/// process takes SIGABRT (exit 134) inside `snapshot_utils.cc` before any Dart
/// code runs. That one is not catchable: the `catch` never executes and the
/// host dies. Deciding *before* the spawn is the only thing that survives it.
///
/// ## Where a hash comes from
///
/// An SDK's is read out of `<sdk>/bin/dartaotruntime`, which contains exactly
/// one lowercase 32-hex string (verified for 3.12.0 and 3.13.2 on
/// macos-arm64). The host's own is baked in at `dart compile exe` time with
/// `--define` and read back through [hostVmSnapshotHash] -- a compiled binary
/// has no `dartaotruntime` beside it to read, and its own bytes are not a
/// reliable source: a small test binary happened to contain exactly one 32-hex
/// run, but nothing guarantees that for a real payload.

/// The number of hex characters in a VM snapshot hash.
const _hashLength = 32;

/// How much of the file to read at a time. An SDK's `dartaotruntime` is
/// megabytes and a compiled host binary can be hundreds of them, so the scan
/// streams rather than reading the whole thing into memory.
const _chunkSize = 64 * 1024;

/// The VM snapshot hash embedded in the file at [path], or `null` when the
/// file cannot answer unambiguously.
///
/// Scans the raw bytes for maximal runs of lowercase ASCII hex and returns the
/// value only when the file holds exactly one *distinct* 32-character run. The
/// same value appearing several times is still one answer; two different
/// values are not.
///
/// Both "no match" and "more than one match" are `null`, deliberately, and
/// callers must treat `null` as UNKNOWN rather than as mismatch. An ambiguous
/// binary is one this cannot read, and guessing which of two candidates is the
/// snapshot hash would turn a guard into a coin flip -- refusing to spawn on a
/// wrong guess is a worse outcome than the crash it is trying to prevent,
/// because it is silent and permanent.
///
/// A run of 31 or 33 hex characters is not a match. Uppercase is not a match:
/// the VM writes the hash lowercase, and accepting uppercase only widens the
/// set of unrelated strings that can collide with it.
///
/// Never throws, and the `on Object` that guarantees it is deliberate. A file
/// that is absent, unreadable, or vanishes mid-scan is `null` for the same
/// reason as an ambiguous one -- this runs in front of a spawn, and a check
/// that takes down the thing it is checking is worse than no check. The catch
/// is that broad because the failures are not all `FileSystemException`:
/// calling this from a scope without `fs` throws a bare `StateError`, which
/// cost a debugging round on the first real call site. Same trade, and the
/// same shape, as `MessageContractHash.compute`.
String? vmSnapshotHashOfFile(String path) {
  try {
    return _hashOfFile(path);
  } on Object {
    return null;
  }
}

String? _hashOfFile(String path) {
  final File file = fs.file(path);
  if (!file.existsSync()) return null;

  RandomAccessFile? handle;
  try {
    handle = file.openSync();
    return _scan(handle);
  } finally {
    try {
      handle?.closeSync();
    } on Object {
      // Nothing useful to do with a failure to close a file we only read.
    }
  }
}

/// The single distinct 32-hex run in [handle], or `null`.
String? _scan(RandomAccessFile handle) {
  final chunk = Uint8List(_chunkSize);

  // Only the first [_hashLength] bytes of a run are ever needed: a longer run
  // is discarded whole, so there is nothing to keep past that point. This is
  // what bounds the memory of the scan to the chunk plus 32 bytes regardless
  // of file size.
  final run = Uint8List(_hashLength);
  var runLength = 0;
  String? found;

  // Set when a second, different value turns up. The scan stops there: the
  // answer is already `null` and cannot become anything else, and the file
  // being read may be hundreds of megabytes.
  var ambiguous = false;

  void endRun() {
    if (runLength == _hashLength) {
      final candidate = String.fromCharCodes(run);
      if (found == null) {
        found = candidate;
      } else if (found != candidate) {
        ambiguous = true;
      }
    }
    runLength = 0;
  }

  while (!ambiguous) {
    final read = handle.readIntoSync(chunk);
    if (read <= 0) break;

    for (var i = 0; i < read; i++) {
      final byte = chunk[i];
      if (_isLowerHexByte(byte)) {
        // Past 32 the run is already disqualified, but the length still has to
        // keep counting so the run is not mistaken for a 32-length one when it
        // ends.
        if (runLength < _hashLength) run[runLength] = byte;
        runLength++;
        continue;
      }
      endRun();
      if (ambiguous) return null;
    }
  }

  if (ambiguous) return null;

  // End of file terminates the last run the same way a non-hex byte would.
  endRun();
  return ambiguous ? null : found;
}

/// `0`-`9`, `a`-`f`. Uppercase is excluded on purpose; see
/// [vmSnapshotHashOfFile].
bool _isLowerHexByte(int byte) =>
    (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x66);

/// The VM snapshot hash of the SDK that [dartExecutablePath] belongs to, or
/// `null` when it cannot be determined.
///
/// The hash is read from the `dartaotruntime` sitting beside the given `dart`,
/// because that is the runtime the SDK's own `dart compile aot-snapshot`
/// output is built to be loaded by.
///
/// [dartExecutablePath] is whatever `DartExecutable.resolve()` returned, and
/// that is not always a path: its last candidate is the bare name `dart`,
/// which it accepts once `dart --version` runs, without ever learning where on
/// `PATH` the answer came from. So a bare name is resolved against `PATH`
/// here, in the same order the shell would.
///
/// Symlinks are followed as a fallback because the common SDK managers install
/// exactly that shape -- a `dart` on `PATH` pointing into a versioned SDK
/// directory. The literal sibling is preferred when it exists, since that is
/// the runtime an invocation of this `dart` would actually reach for.
///
/// `null` when no `dartaotruntime` is found beside any candidate, or when the
/// one found is ambiguous. As everywhere in this file, that means UNKNOWN, and
/// as with [vmSnapshotHashOfFile] this never throws.
String? sdkVmSnapshotHash(String dartExecutablePath) {
  try {
    return _sdkHash(dartExecutablePath);
  } on Object {
    return null;
  }
}

String? _sdkHash(String dartExecutablePath) {
  for (final dart in _dartExecutableCandidates(dartExecutablePath)) {
    final sibling = fs.path.join(
      fs.path.dirname(dart),
      _dartaotruntimeNameBeside(dart),
    );
    if (!fs.file(sibling).existsSync()) continue;
    return vmSnapshotHashOfFile(sibling);
  }
  return null;
}

/// The paths [dartExecutablePath] could name, most specific first.
Iterable<String> _dartExecutableCandidates(String dartExecutablePath) sync* {
  final trimmed = dartExecutablePath.trim();
  if (trimmed.isEmpty) return;

  // A single segment and nothing else is a `PATH` lookup. `./dart` splits into
  // two segments and is a real relative path, so it does not come through
  // here.
  if (fs.path.split(trimmed).length > 1) {
    yield* _withSymlinkTarget(trimmed);
    return;
  }

  final path = Platform.environment['PATH'];
  if (path == null) return;
  for (final entry in path.split(Platform.isWindows ? ';' : ':')) {
    if (entry.isEmpty) continue;
    yield* _withSymlinkTarget(fs.path.join(entry, trimmed));
  }
}

/// [candidate], then what it resolves to if it is a link.
Iterable<String> _withSymlinkTarget(String candidate) sync* {
  yield candidate;
  try {
    final resolved = fs.file(candidate).resolveSymbolicLinksSync();
    if (resolved != candidate) yield resolved;
  } on FileSystemException {
    // Absent or unreadable. The caller's own existence check answers that.
  }
}

/// `dartaotruntime`, carrying over the `.exe` suffix when [dart] has one.
String _dartaotruntimeNameBeside(String dart) =>
    fs.path.basename(dart).toLowerCase().endsWith('.exe')
    ? 'dartaotruntime.exe'
    : 'dartaotruntime';

/// Baked in by `dart compile exe --define=ZONAI_VM_HASH=...`.
///
/// A `const` read, not `String.fromEnvironment(...)` called at runtime: only
/// the const form is resolved at compile time, which is both what makes the
/// define land in the binary at all and what keeps it from being tree-shaken
/// away.
const _hostVmSnapshotHash = String.fromEnvironment('ZONAI_VM_HASH');

/// Baked in by `dart compile exe --define=ZONAI_DART_SDK=...`.
const _hostDartSdkVersion = String.fromEnvironment('ZONAI_DART_SDK');

/// The VM snapshot hash of the SDK this binary was compiled with, or `null`
/// when it was not baked in.
///
/// `null` for any zonai running from source on the Dart VM, and for a binary
/// built without the define -- neither is a mismatch, and callers treat it the
/// same way they treat an unreadable SDK.
String? get hostVmSnapshotHash =>
    _hostVmSnapshotHash.isEmpty ? null : _hostVmSnapshotHash;

/// The Dart SDK version string this binary was compiled with, or `null`.
///
/// For message text only: it is what lets a refusal say "requires Dart 3.12.0,
/// you are on 3.13.2" instead of printing two hex strings at somebody. It is
/// never compared -- [hostVmSnapshotHash] is the comparison, and a version
/// that disagrees with the hash is the version being wrong, not the hash.
String? get hostDartSdkVersion =>
    _hostDartSdkVersion.isEmpty ? null : _hostDartSdkVersion;
