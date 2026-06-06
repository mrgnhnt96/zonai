// Generates lib/gen/native/resqlite_native.g.dart from the prebuilt shared library.
//
// Run from apps/zonai after building the native library:
//   dart run tool/generate_resqlite_native.dart
//
// Pass --check to exit 1 when generated files are out of date (for CI).

import 'dart:io';

import 'package:resqlite/resqlite.dart';

void main(List<String> args) {
  final checkOnly = args.contains('--check');
  final packageRoot = Directory.current.absolute;
  final nativeDir = Directory('${packageRoot.path}/lib/gen/native');
  final libraryFile = File('${nativeDir.path}/$defaultLibraryFileName');
  final generatedFile = File('${nativeDir.path}/resqlite_native.g.dart');

  if (!libraryFile.existsSync()) {
    stderr.writeln(
      '${libraryFile.path} is missing.\n'
      'Run the resqlite native build first (see scripts.yaml resqlite.gen).',
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
        'Run: dart run tool/generate_resqlite_native.dart',
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
// Embedded resqlite native library for compiled Zonai builds.
//
// Regenerate:
//   scripts resqlite gen
//   (or) dart run tool/generate_resqlite_native.dart

import 'dart:typed_data';

const resqliteNativeLibraryBytes = <int>[
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
    'Uint8List get resqliteNativeLibraryBytesList => '
    'Uint8List.fromList(resqliteNativeLibraryBytes);',
  );
  return b.toString();
}
