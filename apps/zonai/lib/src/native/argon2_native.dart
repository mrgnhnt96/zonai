import 'dart:io';

import 'package:zonai/src/domain/constants.dart';

import '../../gen/native/argon2_native.g.dart';
import '../deps/fs.dart';
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
  return switch (kIsCompiled) {
    true => _extractCompiledLibrary(),
    false => _syncNativeAssetLibrary(_developmentLibraryPath()),
  };
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

Future<void> _writeLibraryBytes(File dest, List<int> bytes) async {
  dest.parent.createSync(recursive: true);
  await dest.writeAsBytes(bytes, flush: true);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['755', dest.path]);
  }
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
