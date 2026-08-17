// dart format width=100
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
import 'package:zonai/src/domain/project/project_identity.dart';
import 'package:zonai/src/domain/project/project_binary.dart';
import 'package:zonai/src/domain/project/project_generator.dart';
import 'package:zonai/src/domain/project/project_link.dart';
import 'package:zonai/src/domain/rules/rule_generator.dart';
import 'package:zonai/src/utils/dart_sdk.dart';

export 'package:zonai/src/db_mutator/host_worker_registries.dart'
    show kForceWorkersEnv, HostWorkerRegistries;
export 'package:zonai/src/domain/project/project_link.dart';

/// Commands that should run through the project-linked entry (in-process
/// ops/rules) when launched from the bootstrap CLI.
bool commandNeedsProjectRuntime(List<String> path) {
  return switch (path) {
    // `gen` reads the user's registered tables, which only exist in the
    // project-linked entry -- the bootstrap CLI would generate from an empty
    // schema and report success.
    ['serve', ...] || ['db', ...] || ['dev', ...] || ['gen', ...] => true,
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
  // Only the re-exec is skipped: an entry that cannot resolve `package:zonai`
  // would fail the command outright instead of falling back.
  //
  // `dart run` takes `--packages` just as `dart compile exe` does, so this
  // path gets the merged config too rather than an explanation of why not.
  // Splitting them would be worse than the duplication: `serve` and `db` under
  // dev would keep going out over worker IPC while `build` linked, so the
  // dispatch a developer exercises would stop being the one they ship.
  final link = resolveProjectLink();
  if (link.skipReason case final reason?) {
    logger.debug(
      'Staying on Mailman workers instead of re-exec\'ing the project-linked '
      'entry: $reason',
    );
    return null;
  }

  logOverriddenPackages(link);

  // Both spawns below carry a path that is identical across every zonai
  // project on a machine (`.zonai/zonai`, `dart run
  // .dart_tool/zonai/project_main.dart`), so this is what makes the
  // re-exec'd long-lived server attributable from outside. See
  // project_identity.dart for why it is appended rather than prepended.
  final identityArgs = projectIdentityArgs();

  if (args.release) {
    final code = await ProjectBinary().compile(link: link);
    if (code != 0) return code;

    final exe = settings.compiledProjectBinaryPath;
    logger.info('Starting project binary: $exe');
    final child = await process.start(exe, [
      ...args.original,
      ...identityArgs,
    ], mode: ProcessStartMode.inheritStdio);
    return child.exitCode;
  }

  final dart = await resolveDartExecutable();
  final entry = ProjectGenerator.executablePath;
  logger.info('Starting project entry (JIT): $entry');
  final child = await process.start(dart, [
    'run',
    if (link.packageConfigPath case final packages?) '--packages=$packages',
    entry,
    ...args.original,
    ...identityArgs,
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
