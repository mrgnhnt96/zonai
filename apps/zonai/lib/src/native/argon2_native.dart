import 'dart:io';

import 'package:zonai/src/domain/constants.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart'
    show NativeLibraryKind, nativeLibraryHost;

import '../../gen/native/argon2_native.g.dart';
import '../deps/fs.dart';
import '../domain/native_library_format.dart';
import '../domain/native_library_stamp.dart';
import '../domain/settings.dart';
import 'argon2_ffi.dart' as argon2_ffi;

/// Resolves the absolute path of the native Argon2 (libsodium) library on
/// disk, extracting/syncing it there first if needed (the dev/compiled
/// split mirrors resqlite's own native-library install logic).
///
/// Deliberately does **not** call `argon2_ffi.install()` itself: the actual
/// hashing runs inside an `Isolate.run` closure (see hash_password.dart),
/// and a spawned isolate has no `Zone`/scoped_deps context at all -- the
/// `fs` provider this function needs is unavailable there. So path
/// resolution (this function, using `fs`) must happen on the calling
/// isolate; only the plain path *string* crosses into the spawned isolate,
/// where `argon2_ffi.install(path)` (pure `dart:ffi`/`dart:io`, no
/// scoped_deps) does the actual `dlopen`.
///
/// `async` on purpose, even though both branches already return a Future:
/// without it, [_developmentLibraryPath]'s synchronous throw (no library
/// built yet) would escape as a synchronous exception before this function
/// ever returns a Future, bypassing callers' `.then(onError: ...)` entirely.
Future<String> resolveArgon2NativeLibraryPath() async {
  return await _requestFromSpawner() ?? await provideArgon2NativeLibraryPath();
}

/// Asks the spawning `zonai` process to confirm/refresh the shared Argon2
/// native library and report its path.
///
/// Mirrors resqlite_native.dart's `_requestFromSpawner` -- see there for the
/// full rationale. Returns `null` (fall back to self-extraction) when
/// there's no spawner to ask, the request times out, or the spawner reports
/// failure.
Future<String?> _requestFromSpawner() async {
  try {
    return await nativeLibraryHost
        .request(NativeLibraryKind.argon2)
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    return null;
  }
}

/// Ensures the *spawner's own* embedded Argon2 native library is present at
/// the shared install path and returns that path. Spawner-side half of the
/// ask-your-spawner protocol -- see resqlite_native.dart's
/// `provideResqliteNativeLibraryPath` for the full rationale, including why
/// this is memoized per process (5 `Mailman`s can each receive a
/// `NativeLibraryRequest` and call this concurrently) and why
/// [_writeLibraryBytes] writes via rename instead of in place.
Future<String> provideArgon2NativeLibraryPath() {
  return _installFuture ??= _provideArgon2NativeLibraryPath();
}

Future<String>? _installFuture;

Future<String> _provideArgon2NativeLibraryPath() async {
  try {
    return switch (kIsCompiled) {
      true => await _extractCompiledLibrary(),
      false => await _syncNativeAssetLibrary(_developmentLibraryPath()),
    };
  } catch (e) {
    _installFuture = null;
    rethrow;
  }
}

Future<String> _extractCompiledLibrary() async {
  final libDir = fs.directory(
    fs.path.join(Settings.defaultZonaiDirectory, 'lib'),
  );
  if (!libDir.existsSync()) {
    libDir.createSync(recursive: true);
  }

  final dest = fs.file(
    fs.path.join(libDir.path, argon2_ffi.defaultLibraryFileName),
  );

  // See the matching guard in resqlite_native.dart: a stamped library here
  // was placed for this target by `zonai build`, and is correct where this
  // binary's cross-compiled embedded bytes are not.
  if (hasCurrentNativeLibraryStamp(dest.path)) {
    return dest.absolute.path;
  }

  // See the matching guard in resqlite_native.dart: nothing vouches for the
  // file at this path, so these embedded bytes become the shared copy -- and
  // they are only correct if this binary was compiled for the platform it is
  // running on.
  checkNativeLibraryPlatform(
    argon2NativeLibraryBytes,
    name: 'argon2',
    destination: dest.path,
  );

  await _writeLibraryBytes(dest, argon2NativeLibraryBytes);

  return dest.absolute.path;
}

Future<String> _syncNativeAssetLibrary(String sourcePath) async {
  final source = fs.file(sourcePath);
  final dest = fs.file(
    fs.path.join(
      fs.currentDirectory.path,
      '.dart_tool',
      'lib',
      argon2_ffi.defaultLibraryFileName,
    ),
  );

  if (!source.existsSync()) {
    throw StateError('Argon2 native library not found at $sourcePath');
  }

  if (dest.existsSync() &&
      dest.lengthSync() == source.lengthSync() &&
      !source.lastModifiedSync().isAfter(dest.lastModifiedSync())) {
    return dest.absolute.path;
  }

  await _writeLibraryBytes(dest, await source.readAsBytes());
  return dest.absolute.path;
}

/// Writes [bytes] to [dest] via a same-directory temp file + rename -- see
/// resqlite_native.dart's `_writeLibraryBytes` for why this needs to be
/// atomic rather than an in-place truncate + write.
Future<void> _writeLibraryBytes(File dest, List<int> bytes) async {
  dest.parent.createSync(recursive: true);

  final tempFile = File(
    '${dest.path}.tmp-$pid-${Object().hashCode.toRadixString(36)}',
  );
  await tempFile.writeAsBytes(bytes, flush: true);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['755', tempFile.path]);
  }
  await tempFile.rename(dest.path);
}

String _developmentLibraryPath() {
  final candidates = _developmentLibraryCandidates();

  for (final path in candidates) {
    final file = fs.file(path);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }

  throw StateError(
    'Argon2 native library not found.\n'
    'Searched:\n${candidates.map((path) => '  - $path').join('\n')}\n'
    'Run: scripts argon2 gen',
  );
}

List<String> _developmentLibraryCandidates() {
  final libName = argon2_ffi.defaultLibraryFileName;
  final candidates = <String>[];

  var dir = fs.directory(fs.currentDirectory.path);
  while (true) {
    candidates.addAll([
      fs.path.join(dir.path, 'apps', 'zonai', 'lib', 'gen', 'native', libName),
      fs.path.join(dir.path, 'lib', 'gen', 'native', libName),
    ]);

    if (dir.path == dir.parent.path) {
      break;
    }
    dir = dir.parent;
  }

  if (Platform.script.scheme == 'file') {
    candidates.add(
      fs.path.normalize(
        fs.path.join(
          fs.file(Platform.script.toFilePath()).parent.path,
          '..',
          'lib',
          'gen',
          'native',
          libName,
        ),
      ),
    );
  }

  return candidates;
}
