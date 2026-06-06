import 'dart:convert';
import 'dart:io';

/// Whether [Platform.script] is a `dart run` kernel snapshot.
bool get runningFromKernelSnapshot =>
    Platform.script.toFilePath().endsWith('.snapshot');

/// Source [bin/zonai.dart] for the zonai package, if discoverable.
String? zonaiSourceEntrypoint() {
  for (final configPath in _packageConfigCandidates()) {
    final entry = _entrypointFromPackageConfig(configPath);
    if (entry != null) {
      return entry;
    }
  }

  return _entrypointFromWalkUp();
}

/// Entrypoint for `dart run` subprocesses and snapshot re-exec.
///
/// Kernel snapshots (`dart run zonai`) break resqlite [@Native] FFI after
/// runtime [install]; prefer the package source entrypoint in that case.
String dartRunEntrypoint() {
  final script = Platform.script.toFilePath();
  if (!script.endsWith('.snapshot')) {
    return script;
  }

  final fromConfig = zonaiSourceEntrypoint();
  if (fromConfig != null) {
    return fromConfig;
  }

  throw StateError(
    'Could not resolve zonai source entrypoint for subprocess '
    '(running from snapshot: $script)',
  );
}

/// Re-run from package source when launched via kernel snapshot.
///
/// Returns the child exit code when re-exec ran, or `-1` when not needed.
Future<int> reexecFromSourceIfNeeded(List<String> arguments) async {
  if (!runningFromKernelSnapshot) {
    return -1;
  }

  final entry = zonaiSourceEntrypoint();
  if (entry == null) {
    return -1;
  }

  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    entry,
    ...arguments,
  ], mode: ProcessStartMode.inheritStdio);
  return process.exitCode;
}

Iterable<String> _packageConfigCandidates() sync* {
  final fromPlatform = Platform.packageConfig;
  if (fromPlatform != null) {
    yield fromPlatform;
  }

  for (final dir in _walkUp(Directory.current)) {
    final config = File(
      '${dir.path}${Platform.pathSeparator}.dart_tool'
      '${Platform.pathSeparator}package_config.json',
    );
    if (config.existsSync()) {
      yield config.path;
    }
  }

  if (Platform.script.scheme == 'file') {
    for (final dir in _walkUp(Directory(Platform.script.toFilePath()).parent)) {
      final config = File(
        '${dir.path}${Platform.pathSeparator}.dart_tool'
        '${Platform.pathSeparator}package_config.json',
      );
      if (config.existsSync()) {
        yield config.path;
      }
    }
  }
}

String? _entrypointFromPackageConfig(String configPath) {
  final configFile = File(configPath);
  if (!configFile.existsSync()) {
    return null;
  }

  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final packages = config['packages'] as List<dynamic>;
  for (final raw in packages) {
    final pkg = raw as Map<String, dynamic>;
    if (pkg['name'] != 'zonai') {
      continue;
    }

    final rootUri = pkg['rootUri'] as String;
    final packageRoot = configFile.parent.uri
        .resolve(rootUri)
        .toFilePath(windows: Platform.isWindows);
    final entrypoint = [
      packageRoot,
      'bin',
      'zonai.dart',
    ].join(Platform.pathSeparator);

    if (File(entrypoint).existsSync()) {
      return entrypoint;
    }
  }

  return null;
}

String? _entrypointFromWalkUp() {
  const relativeEntrypoints = [
    ['apps', 'zonai', 'bin', 'zonai.dart'],
    ['bin', 'zonai.dart'],
  ];

  for (final start in _searchRoots()) {
    for (final dir in _walkUp(start)) {
      for (final parts in relativeEntrypoints) {
        final entry = [dir.path, ...parts].join(Platform.pathSeparator);
        if (File(entry).existsSync()) {
          return entry;
        }
      }
    }
  }

  return null;
}

Iterable<Directory> _searchRoots() sync* {
  yield Directory.current;

  if (Platform.script.scheme == 'file') {
    yield Directory(Platform.script.toFilePath()).parent;
  }
}

Iterable<Directory> _walkUp(Directory start) sync* {
  var dir = start;
  while (true) {
    yield dir;
    if (dir.path == dir.parent.path) {
      break;
    }
    dir = dir.parent;
  }
}
