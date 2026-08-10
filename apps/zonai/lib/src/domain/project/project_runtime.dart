// dart format width=100
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:zonai/src/db_mutator/host_worker_registries.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/operations/operation_generator.dart';
import 'package:zonai/src/domain/project/project_binary.dart';
import 'package:zonai/src/domain/project/project_generator.dart';
import 'package:zonai/src/domain/rules/rule_generator.dart';
import 'package:zonai/src/utils/dart_sdk.dart';

export 'package:zonai/src/db_mutator/host_worker_registries.dart'
    show kForceWorkersEnv, HostWorkerRegistries;

/// Commands that should run through the project-linked entry (in-process
/// ops/rules) when launched from the bootstrap CLI.
bool commandNeedsProjectRuntime(List<String> path) {
  return switch (path) {
    ['serve', ...] || ['db', ...] || ['dev', ...] => true,
    _ => false,
  };
}

bool get forceWorkers => HostWorkerRegistries.forceWorkers;

/// Whether `package:zonai` resolves from the project being built or served.
///
/// The generated project entry imports `package:zonai/src/bootstrap.dart`
/// (see [ProjectGenerator]), so it can only be compiled -- or JIT-run --
/// from inside a package graph that contains zonai itself. Projects get
/// that from a `zonai: {path: ...}` dev dependency, as apps/playground has.
///
/// A project depending on `zonai_schema` alone is the common case for real
/// deployments (zonai ships as a standalone binary, not a pub dependency),
/// and there is nothing to fix about that: those projects run ops/rules as
/// Mailman workers instead. Callers use this to choose that path up front
/// rather than emitting an entry that cannot resolve its own imports.
bool projectResolvesZonai() {
  for (final path in _packageConfigCandidates()) {
    final file = fs.file(path);
    if (!file.existsSync()) continue;

    try {
      if (json.decode(file.readAsStringSync()) case {'packages': final List<dynamic> packages}) {
        return packages.any((package) => package is Map && package['name'] == 'zonai');
      }
    } catch (_) {
      // An unreadable or half-written package_config is not a linkable
      // project; fall back to workers rather than failing the build.
    }

    // The nearest config is the one pub resolved this project against;
    // an ancestor's is a different resolution and answers a different
    // question, so don't keep walking past it.
    return false;
  }

  return false;
}

/// `.dart_tool/package_config.json` candidates, nearest first.
///
/// A pub workspace writes exactly one package config, at the workspace root
/// -- members get none. So the project being built is very often a directory
/// with no `.dart_tool` of its own (apps/playground here, apps/server in a
/// consumer repo), and looking only beside its pubspec would report every
/// workspace member as unable to link.
Iterable<String> _packageConfigCandidates() sync* {
  var dir = fs.file(settings.packageConfigPath).parent.parent.absolute;

  while (true) {
    yield fs.path.join(dir.path, '.dart_tool', 'package_config.json');

    if (dir.path == dir.parent.path) return;
    dir = dir.parent;
  }
}

/// Generates ops/rules factories + [project_main.dart].
Future<void> generateProjectEntry() async {
  await OperationGenerator(
    operations: _dartFiles(settings.operationsPath),
    schemasPath: settings.schemasPath,
  ).create();
  await RuleGenerator(rules: _dartFiles(settings.rulesPath)).create();
  await const ProjectGenerator().create();
}

/// When bootstrap CLI handles serve/db/dev without in-process registries,
/// re-exec into the project-linked entry (JIT) or compiled project binary
/// (`--release`).
///
/// Published AOT bootstrap binaries (`kIsCompiled`) stay in-process and use
/// Mailman workers for ops/rules — they do not ship `lib/gen/` and cannot
/// JIT-compile the path-dep package. Project-linked `build/zonai` already
/// has registries set and returns earlier via [HostWorkerRegistries.hasOperations].
///
/// Returns the child exit code, or `null` when the current process should
/// continue (already linked, compiled bootstrap, forced workers, or
/// non-project command).
Future<int?> maybeReexecProjectRuntime() async {
  if (HostWorkerRegistries.hasOperations) return null;
  if (kIsCompiled) return null;
  if (forceWorkers) return null;
  if (!commandNeedsProjectRuntime(args.path)) return null;

  // Require a project root (config or schemas) so `zonai version` etc. stay
  // on the bootstrap binary.
  final hasConfig = fs.file('zonai.yml').existsSync() || fs.file('zonai.yaml').existsSync();
  final hasSchemas = fs.directory(settings.schemasPath).existsSync();
  if (!hasConfig && !hasSchemas) return null;

  await generateProjectEntry();

  // Generation above is unconditional -- the worker sources it writes are
  // what the Mailman/isolate path spawns, so they are needed either way.
  // Only the re-exec is skipped: `dart run project_main.dart` cannot resolve
  // `package:zonai` from a project that doesn't depend on it, and would fail
  // the command outright instead of falling back.
  if (!projectResolvesZonai()) {
    logger.debug(
      'package:zonai is not resolvable from this project -- staying on '
      'Mailman workers instead of re-exec\'ing the project-linked entry.',
    );
    return null;
  }

  if (args.release) {
    final code = await ProjectBinary().compile();
    if (code != 0) return code;

    final exe = settings.compiledProjectBinaryPath;
    logger.info('Starting project binary: $exe');
    final child = await process.start(exe, args.original, mode: ProcessStartMode.inheritStdio);
    return child.exitCode;
  }

  final dart = await resolveDartExecutable();
  final entry = ProjectGenerator.executablePath;
  logger.info('Starting project entry (JIT): $entry');
  final child = await process.start(dart, [
    'run',
    entry,
    ...args.original,
  ], mode: ProcessStartMode.inheritStdio);
  return child.exitCode;
}

List<File> _dartFiles(String path) {
  final directory = fs.directory(path);
  if (!directory.existsSync()) return const [];
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => fs.path.extension(file.path) == '.dart')
      .toList();
}
