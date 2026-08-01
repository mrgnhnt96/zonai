// dart format width=100
import 'dart:io';

import 'package:file/file.dart';
import 'package:zonai/src/db_mutator/host_worker_registries.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/settings.dart';
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
/// Returns the child exit code, or `null` when the current process should
/// continue (already linked, forced workers, or non-project command).
Future<int?> maybeReexecProjectRuntime() async {
  if (HostWorkerRegistries.hasOperations) return null;
  if (forceWorkers) return null;
  if (!commandNeedsProjectRuntime(args.path)) return null;

  // Require a project root (config or schemas) so `zonai version` etc. stay
  // on the bootstrap binary.
  final hasConfig =
      fs.file('zonai.yml').existsSync() || fs.file('zonai.yaml').existsSync();
  final hasSchemas = fs.directory(settings.schemasPath).existsSync();
  if (!hasConfig && !hasSchemas) return null;

  await generateProjectEntry();

  if (args.release) {
    final code = await ProjectBinary().compile();
    if (code != 0) return code;

    final exe = settings.compiledProjectBinaryPath;
    logger.info('Starting project binary: $exe');
    final child = await process.start(
      exe,
      args.original,
      mode: ProcessStartMode.inheritStdio,
    );
    return child.exitCode;
  }

  final dart = await resolveDartExecutable();
  final entry = ProjectGenerator.executablePath;
  logger.info('Starting project entry (JIT): $entry');
  final child = await process.start(
    dart,
    ['run', entry, ...args.original],
    mode: ProcessStartMode.inheritStdio,
  );
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
