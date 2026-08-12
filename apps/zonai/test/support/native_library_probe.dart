// A binary whose only job is to run the compiled-mode native library
// extraction and say where it landed.
//
// `kIsCompiled` is `bool.fromEnvironment('__ZONAI_COMPILED__')`, which is a
// compile-time constant `false` under `dart test`. That makes
// `_extractCompiledLibrary` -- and the stamp guard inside it that decides
// whether a library `zonai build` placed for a cross-compiled target survives
// -- unreachable from any in-process test, however it is written. The only way
// to execute that branch is to compile something with the define set.
//
// This is compiled instead of `bin/zonai.dart` so the test exercises exactly
// the one decision it is about, with no command, project or server around it.
// [provideResqliteNativeLibraryPath] only resolves and returns a path; it never
// dlopens the result, which is what lets the test plant a recognisable
// non-library file and read back whether the guard kept it.
//
// Compiled by test/src/native/native_library_extraction_compiled_e2e_test.dart.

import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/native/argon2_native.dart';
import 'package:zonai/src/native/resqlite_native.dart';

Future<void> main(List<String> args) async {
  final library = args.isEmpty ? 'resqlite' : args.first;

  // Only [fsProvider], because that is the one dependency the extraction path
  // reads. `bootstrap.dart` establishes a much larger scope; borrowing it here
  // would drag the CLI's argument parsing and logging into a binary whose whole
  // point is that nothing but the guard runs.
  await runScoped(() async {
    final path = switch (library) {
      'resqlite' => await provideResqliteNativeLibraryPath(),
      'argon2' => await provideArgon2NativeLibraryPath(),
      _ => throw ArgumentError.value(library, 'library'),
    };
    stdout.writeln(path);
  }, values: {fsProvider});
}
