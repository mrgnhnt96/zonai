// Builds the native Argon2 (libsodium) library for the current platform
// into lib/gen/native/, so tool/generate_argon2_native.dart can embed it.
//
// Run from apps/zonai:
//   dart run tool/build_argon2_native.dart
//
// This shells out to `dart build cli` inside tool/native/argon2_builder --
// a throwaway helper package whose only job is to depend on `sodium` so its
// build hook compiles libsodium's vendored, official C source for us. We
// don't depend on `sodium` at runtime; we just take the compiled library
// file it produces. See tool/native/argon2_builder/pubspec.yaml.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zonai/src/native/argon2_ffi.dart' as argon2_ffi;

Future<void> main() async {
  final zonaiRoot = Directory.current.absolute;
  final builderDir = Directory(
    p.join(zonaiRoot.path, 'tool', 'native', 'argon2_builder'),
  );

  if (!builderDir.existsSync()) {
    stderr.writeln('${builderDir.path} is missing.');
    exit(1);
  }

  print('Fetching argon2_builder dependencies...');
  await _run('dart', ['pub', 'get'], builderDir.path);

  print('Building native libsodium (dart build cli)...');
  await _run('dart', ['build', 'cli'], builderDir.path);

  final builtLibrary = _findBuiltLibrary(builderDir);
  if (builtLibrary == null) {
    stderr.writeln(
      'Could not find a built native library under '
      '${builderDir.path}/build/cli/*/bundle/lib/',
    );
    exit(1);
  }

  final destDir = Directory(p.join(zonaiRoot.path, 'lib', 'gen', 'native'))
    ..createSync(recursive: true);
  final dest = File(p.join(destDir.path, argon2_ffi.defaultLibraryFileName));
  builtLibrary.copySync(dest.path);

  print('Wrote ${dest.path} (${dest.lengthSync()} bytes)');
}

File? _findBuiltLibrary(Directory builderDir) {
  final bundleRoot = Directory(p.join(builderDir.path, 'build', 'cli'));
  if (!bundleRoot.existsSync()) return null;

  for (final platformDir in bundleRoot.listSync().whereType<Directory>()) {
    final libDir = Directory(p.join(platformDir.path, 'bundle', 'lib'));
    if (!libDir.existsSync()) continue;

    final libraryFiles = libDir.listSync().whereType<File>().where(
      (f) =>
          f.path.endsWith('.dylib') ||
          f.path.endsWith('.so') ||
          f.path.endsWith('.dll'),
    );
    if (libraryFiles.isNotEmpty) return libraryFiles.first;
  }
  return null;
}

Future<void> _run(String executable, List<String> args, String cwd) async {
  final result = await Process.run(executable, args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    stderr.writeln('${result.stdout}\n${result.stderr}');
    exit(result.exitCode);
  }
}
