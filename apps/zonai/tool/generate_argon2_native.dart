// Generates lib/gen/native/argon2_native.g.dart from the prebuilt shared
// library produced by tool/build_argon2_native.dart.
//
// Run from apps/zonai after building the native library:
//   dart run tool/generate_argon2_native.dart
//
// Pass --check to exit 1 when generated files are out of date (for CI).

import 'dart:io';

import 'package:zonai/src/native/argon2_ffi.dart' as argon2_ffi;

void main(List<String> args) {
  final checkOnly = args.contains('--check');
  final packageRoot = Directory.current.absolute;
  final nativeDir = Directory('${packageRoot.path}/lib/gen/native');
  final libraryFile = File(
    '${nativeDir.path}/${argon2_ffi.defaultLibraryFileName}',
  );
  final generatedFile = File('${nativeDir.path}/argon2_native.g.dart');

  if (!libraryFile.existsSync()) {
    stderr.writeln(
      '${libraryFile.path} is missing.\n'
      'Run the argon2 native build first (see scripts.yaml argon2.gen).',
    );
    exit(1);
  }

  final output = _formatDart(libraryFile.readAsBytesSync());

  if (checkOnly) {
    final existing = generatedFile.existsSync()
        ? generatedFile.readAsStringSync()
        : '';
    if (existing != output) {
      stderr.writeln(
        '${generatedFile.path} is out of date. '
        'Run: dart run tool/generate_argon2_native.dart',
      );
      exit(1);
    }
    stdout.writeln('${generatedFile.path} is up to date.');
    return;
  }

  if (!nativeDir.existsSync()) {
    nativeDir.createSync(recursive: true);
  }

  generatedFile.writeAsStringSync(output);
  stdout.writeln('Wrote ${generatedFile.path}');
  stdout.writeln(
    '  ${libraryFile.lengthSync()} bytes from ${libraryFile.path}',
  );
}

String _formatDart(List<int> bytes) {
  final b = StringBuffer('''
// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Embedded native Argon2 (libsodium) library for compiled Zonai builds.
//
// Regenerate:
//   scripts argon2 gen
//   (or) dart run tool/build_argon2_native.dart
//        dart run tool/generate_argon2_native.dart

import 'dart:typed_data';

const argon2NativeLibraryBytes = <int>[
''');

  for (var i = 0; i < bytes.length; i++) {
    if (i % 16 == 0) {
      b.write('\n  ');
    }
    b.write('${bytes[i]},');
  }

  b.writeln('\n];');
  b.writeln('');
  b.writeln(
    'Uint8List get argon2NativeLibraryBytesList => '
    'Uint8List.fromList(argon2NativeLibraryBytes);',
  );
  return b.toString();
}
