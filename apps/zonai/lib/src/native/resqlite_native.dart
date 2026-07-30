import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart'
    show NativeLibraryKind, nativeLibraryHost;

import '../../gen/native/resqlite_native.g.dart';
import '../deps/fs.dart';
import '../domain/settings.dart';

/// Ensures the resqlite native library is loaded before any FFI use.
///
/// Prefers asking whatever spawned this process to confirm/refresh the
/// shared native library first (see [_requestFromSpawner]); only falls back
/// to extracting this process's own embedded copy when there's no spawner
/// to ask (e.g. this *is* the top-level `zonai`/`zonai serve` process) or
/// the ask fails.
Future<void> ensureResqliteNativeInstalled() async {
  if (isInstalled) return;

  install(await _resolveInstallPath());
}

Future<String> _resolveInstallPath() async {
  return await _requestFromSpawner() ?? await provideResqliteNativeLibraryPath();
}

/// Asks the spawning `zonai` process to confirm/refresh the shared resqlite
/// native library and report its path.
///
/// A worker executable is `dart compile exe --target-os X --target-arch Y`
/// compiled locally, from the *local* zonai package source; the resulting
/// executable format is correctly cross-compiled, but the native-library
/// bytes embedded as Dart constants are just data baked in by whatever host
/// ran the build -- unaffected by `--target-os`/`--target-arch`, and not
/// necessarily a match for wherever the worker actually ends up running.
/// The spawner (the `zonai serve` process, or a `zonai` process running a
/// command directly) is always running natively on this machine, so its own
/// embedded copy is guaranteed correct here -- ask it instead of trusting
/// this process's own possibly-wrong-platform copy.
///
/// Returns `null` (meaning "fall back to self-extraction") when:
///  - there's no spawner to ask -- [nativeLibraryHost] is only registered
///    with a real implementation inside a worker's `MessageHandler.listen`
///    loop, so reading it from the top-level process throws, which we treat
///    as "not a worker, self-extraction is authoritative here";
///  - the request times out; or
///  - the spawner reports failure.
///
/// Uses a generous timeout relative to the 1-second request/reply timeout
/// used elsewhere for already-established, in-memory RPCs: the spawner may
/// need to do a filesystem write (extracting its own embedded bytes) before
/// it can reply, so a tight timeout could spuriously fall back.
Future<String?> _requestFromSpawner() async {
  try {
    return await nativeLibraryHost
        .request(NativeLibraryKind.resqlite)
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    return null;
  }
}

/// Ensures the *spawner's own* embedded resqlite native library is present
/// at the shared install path and returns that path.
///
/// This is the spawner-side half of the ask-your-spawner protocol described
/// on [_requestFromSpawner]: a worker cannot trust the copy embedded in its
/// own executable, but the spawner is always running natively on this
/// machine, so its own embedded copy -- freshly (re-)extracted here -- is
/// guaranteed correct. Also used directly by [ensureResqliteNativeInstalled]
/// itself when there's no spawner above it to ask (it IS the authoritative
/// source in that case).
Future<String> provideResqliteNativeLibraryPath() async {
  return switch (kIsCompiled) {
    true => await _extractCompiledLibrary(),
    false => await _syncNativeAssetLibrary(_developmentLibraryPath()),
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
    fs.path.join(libDir.path, defaultLibraryFileName),
  );
  await _writeLibraryBytes(dest, resqliteNativeLibraryBytes);

  return dest.absolute.path;
}

Future<String> _syncNativeAssetLibrary(String sourcePath) async {
  final source = fs.file(sourcePath);
  final dest = fs.file(
    fs.path.join(
      fs.currentDirectory.path,
      '.dart_tool',
      'lib',
      defaultLibraryFileName,
    ),
  );

  if (!source.existsSync()) {
    throw StateError('Resqlite native library not found at $sourcePath');
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
    'Resqlite native library not found.\n'
    'Searched:\n${candidates.map((path) => '  - $path').join('\n')}\n'
    'Run: scripts resqlite gen',
  );
}

List<String> _developmentLibraryCandidates() {
  final libName = defaultLibraryFileName;
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
