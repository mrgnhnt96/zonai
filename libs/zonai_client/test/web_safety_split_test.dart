// dart format width=100
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Compiles a throwaway entrypoint with `dart compile js` and returns the
/// `.deps` sidecar file's contents -- the literal list of source files that
/// contributed to that build. This is a real compile, not a guess about what
/// a conditional import resolves to: `dart:io`-backed code that leaked into
/// the graph shows up here whether or not it happens to get called.
Future<String> _compileAndGetDeps({required String importLine, required String useLine}) async {
  final packageConfig = _findPackageConfig();
  final tempDir = await Directory.systemTemp.createTemp('zonai_client_web_safety_');
  try {
    final entry = File(p.join(tempDir.path, 'main.dart'));
    await entry.writeAsString('''
$importLine

void main() {
$useLine
}
''');
    final outJs = p.join(tempDir.path, 'main.dart.js');

    final result = await Process.run('dart', [
      'compile',
      'js',
      '--packages=$packageConfig',
      '-o',
      outJs,
      entry.path,
    ]);

    if (result.exitCode != 0) {
      fail('dart compile js failed (exit ${result.exitCode}):\n${result.stdout}\n${result.stderr}');
    }

    final depsFile = File('$outJs.deps');
    expect(depsFile.existsSync(), isTrue, reason: 'expected dart2js to emit a .deps sidecar file');
    return depsFile.readAsStringSync();
  } finally {
    await tempDir.delete(recursive: true);
  }
}

void main() {
  // `dart compile js` takes real compile time (~1-2s each); this file
  // deliberately does exactly two, one per invariant it checks.
  test(
    'importing only package:zonai_client/zonai_client.dart keeps package:file '
    'out of a web build',
    () async {
      final deps = await _compileAndGetDeps(
        importLine: "import 'package:zonai_client/zonai_client.dart';",
        useLine: '''
  final client = ZonaiClient(storage: ZonaiStorage.memory());
  client.health();
''',
      );

      expect(
        deps,
        isNot(contains('zonai_file_storage.dart')),
        reason:
            'lib/src/utils/zonai_file_storage.dart (ZonaiFileStorage, backed by '
            'package:file/local.dart -> dart:io LocalFileSystem) must not be reachable '
            'from a build that only imports the main barrel. See lib/storage.dart\'s '
            'doc comment for why this split exists.',
      );
      expect(
        RegExp(r'\.pub-cache/hosted/pub\.dev/file-').hasMatch(deps),
        isFalse,
        reason: 'package:file itself must not be pulled into a web build of the main barrel.',
      );
    },
  );

  // Positive control: proves the check above is not vacuous by running the
  // exact same compile-and-inspect path against code that *should* pull
  // package:file in, and confirming it actually shows up.
  test(
    'positive control: importing package:zonai_client/storage.dart does pull '
    'package:file in (proves the check above can fail)',
    () async {
      final deps = await _compileAndGetDeps(
        importLine: '''
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_client/storage.dart';
''',
        useLine: '''
  final client = ZonaiClient(storage: ZonaiFileStorage(directory: '/tmp'));
  client.health();
''',
      );

      expect(deps, contains('zonai_file_storage.dart'));
      expect(RegExp(r'\.pub-cache/hosted/pub\.dev/file-').hasMatch(deps), isTrue);
    },
  );
}

/// Walks up from the current working directory to the repo root (identified
/// by `.dart_tool/package_config.json`, written at the workspace root since
/// this package resolves via `resolution: workspace`) and returns its path.
String _findPackageConfig() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final candidate = File(p.join(dir.path, '.dart_tool', 'package_config.json'));
    if (candidate.existsSync()) {
      return candidate.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('Could not find .dart_tool/package_config.json above ${Directory.current.path}');
}
