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

/// The `package_config.json` that resolves `package:zonai` to sources on disk.
///
/// Same candidates and same standard of proof as [zonaiSourceEntrypoint] --
/// a config only counts once `bin/zonai.dart` is confirmed under the root it
/// names -- but it returns the config rather than the entry, because that is
/// what `--packages` takes.
///
/// `null` is the bare-released-binary case: a `zonai` downloaded to a machine
/// that has none of its sources. Nothing can be merged there, and a build has
/// to fall back to worker IPC. That is not a failure to fix, it is the
/// limitation the merge is bounded by.
String? zonaiPackageConfigPath() {
  for (final configPath in _packageConfigCandidates()) {
    if (_entrypointFromPackageConfig(configPath) != null) {
      return configPath;
    }
  }

  return null;
}

/// Generated files under `apps/zonai/lib/gen/` that a linked build compiles
/// against, relative to the zonai package root.
///
/// Every one is gitignored and produced by `zonai compile`, so a *checkout* of
/// zonai has sources without them. `gen/web` is absent on purpose: nothing
/// imports it, so it is not part of what a linked build needs to compile.
const _generatedSources = [
  ['gen', 'version.dart'],
  ['gen', 'native', 'resqlite_native.g.dart'],
  ['gen', 'native', 'argon2_native.g.dart'],
  ['gen', 'server', '.revali', 'server', 'server.dart'],
  ['gen', 'server', 'lib', 'config', 'server_binding.dart'],
];

/// The first generated file a linked build would need and cannot find, or
/// `null` when zonai's sources are complete enough to compile against.
///
/// Sources being *present* is not the same as being *buildable*, and the
/// difference is invisible until `dart compile exe` fails: a zonai checkout
/// that has not been built has `bin/zonai.dart` and a package config -- enough
/// to merge -- but none of `lib/gen/`. Merging then hands the compiler an
/// entry importing files that do not exist, with no fallback, where skipping
/// the link would have run the project over worker IPC and worked.
String? missingZonaiGeneratedSource() {
  final entry = zonaiSourceEntrypoint();
  if (entry == null) return null;

  // `<root>/bin/zonai.dart` -> `<root>/lib`.
  final packageRoot = File(entry).parent.parent.path;
  for (final parts in _generatedSources) {
    final path = [packageRoot, 'lib', ...parts].join(Platform.pathSeparator);
    if (!File(path).existsSync()) {
      return path;
    }
  }

  return null;
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

  // A half-written or hand-edited config is a config that resolves nothing,
  // not a reason to bring the process down: every caller here is choosing
  // between package resolutions and has a fallback for finding none.
  final List<dynamic> packages;
  try {
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    packages = config['packages'] as List<dynamic>;
  } catch (_) {
    return null;
  }

  for (final raw in packages) {
    if (raw is! Map || raw['name'] != 'zonai') {
      continue;
    }

    final rootUri = raw['rootUri'];
    if (rootUri is! String) {
      continue;
    }

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
