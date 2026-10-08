import 'package:file/file.dart';

import '../deps/config.dart';
import '../deps/crons.dart';
import '../deps/env.dart';
import '../deps/extensions.dart';
import '../deps/fs.dart';
import '../deps/logger.dart';
import '../deps/operations.dart';
import '../deps/rate_limits.dart';
import '../deps/rules.dart';
import '../deps/settings.dart';

/// One compiled worker, and the sources it was compiled from.
final class WorkerSources {
  const WorkerSources({
    required this.name,
    required this.executablePath,
    required this.sourcePaths,
    required this.compile,
  });

  /// As the logs name it: `rules`, `config`, ...
  final String name;

  final String executablePath;

  /// Files and directories whose contents the executable is built from. A
  /// path that does not exist is skipped.
  final List<String> sourcePaths;

  /// Rebuilds [executablePath], returning `0` on success.
  final Future<int> Function() compile;
}

/// The serving workers and their sources.
///
/// The same inputs the dev watchers react to (`rules.watch()` and the rest:
/// each worker's own directory, and `schemas/` for operations; `.env` for all
/// of them), plus `pubspec.lock`, since a dependency upgrade changes compiled
/// code too -- zonai_schema 0.6.0's changelog asks for exactly that
/// recompile. Like the watchers, it does not follow imports: a rule that
/// imports a helper from elsewhere in `lib/` is not marked stale when only the
/// helper changes.
///
/// Each compile looks its worker up when it runs, not here, so deciding
/// staleness needs only `settings`, `env` and `fs`.
List<WorkerSources> serveWorkers() {
  final shared = [env.env.file.path, settings.pubspecLockPath];
  return [
    WorkerSources(
      name: 'operations',
      executablePath: settings.compiledOperationsPath,
      sourcePaths: [settings.operationsPath, settings.schemasPath, ...shared],
      compile: () => operations.compile(),
    ),
    WorkerSources(
      name: 'extensions',
      executablePath: settings.compiledExtensionsPath,
      sourcePaths: [settings.extensionsPath, ...shared],
      compile: () => extensions.compile(),
    ),
    WorkerSources(
      name: 'rules',
      executablePath: settings.compiledRulesPath,
      sourcePaths: [settings.rulesPath, ...shared],
      compile: () => rules.compile(),
    ),
    WorkerSources(
      name: 'rate limits',
      executablePath: settings.compiledRateLimitPath,
      sourcePaths: [settings.rateLimitPath, ...shared],
      compile: () => rateLimitsCompiler.compile(),
    ),
    WorkerSources(
      name: 'crons',
      executablePath: settings.compiledCronsPath,
      sourcePaths: [settings.cronsPath, ...shared],
      compile: () => cronsCompiler.compile(),
    ),
    WorkerSources(
      name: 'config',
      executablePath: settings.compiledConfigPath,
      sourcePaths: [settings.configPath, ...shared],
      compile: () => config.compile(),
    ),
  ];
}

/// The workers in [workers] whose executable is missing, or older than
/// something under their [WorkerSources.sourcePaths].
///
/// A worker with no source on disk is never stale: that is a `zonai build`
/// bundle, which ships executables and no sources, and there is nothing to
/// compare its executables against.
List<WorkerSources> findStaleWorkers(Iterable<WorkerSources> workers) => [
  for (final worker in workers)
    if (_isStale(worker)) worker,
];

bool _isStale(WorkerSources worker) {
  final newest = _newestSource(worker.sourcePaths);
  if (newest == null) return false;
  final built = _modified(worker.executablePath);
  return built == null || newest.isAfter(built);
}

/// Makes sure no worker serves code older than its sources.
///
/// In dev, each stale worker is compiled before the server spawns it. The
/// watchers only see edits made while the server runs, so an edit made while
/// it was down used to be served from the old executable until something
/// else triggered a compile (reported against v0.10.1, where the stale
/// worker was a row rule deciding who may delete whose rows).
///
/// Under `--release` nothing is compiled -- release serving is documented as
/// "no recompiling" -- so a stale worker is a refusal: this returns `false`,
/// and serve exits non-zero naming the workers and the fix. A warning would
/// scroll past while the server enforces the old rules. [allowStale] serves
/// anyway, still naming them.
Future<bool> ensureWorkersFresh(
  List<WorkerSources> workers, {
  required bool release,
  required bool allowStale,
}) async {
  final stale = findStaleWorkers(workers);
  if (stale.isEmpty) return true;

  final names = stale.map((worker) => worker.name).join(', ');

  if (release) {
    if (allowStale) {
      logger.warn(
        'Serving workers older than their sources ($names) because of '
        '--allow-stale-workers. They run the code from their last compile.',
      );
      return true;
    }
    logger.error(
      'These workers are older than their sources: $names. `zonai serve '
      '--release` does not compile, so it would serve the code from their '
      'last compile -- rules included. Run `zonai compile`, then serve again. '
      'To serve them as they are, pass --allow-stale-workers.',
    );
    return false;
  }

  logger.info('Sources changed since the last compile: $names');
  for (final worker in stale) {
    try {
      if (await worker.compile() != 0) {
        logger.error(
          'Failed to compile ${worker.name}; serving its last build',
        );
      }
    } catch (error, stack) {
      logger.error('Failed to compile ${worker.name}', error, stack);
    }
  }
  return true;
}

/// The latest modification time of anything under [paths], directories
/// included (a deleted file changes only its directory), or `null` when none
/// of them exists.
DateTime? _newestSource(List<String> paths) {
  DateTime? newest;
  void consider(DateTime time) {
    if (newest == null || time.isAfter(newest!)) newest = time;
  }

  for (final path in paths) {
    switch (fs.typeSync(path)) {
      case FileSystemEntityType.file:
        consider(fs.file(path).statSync().modified);
      case FileSystemEntityType.directory:
        final directory = fs.directory(path);
        consider(directory.statSync().modified);
        for (final entity in directory.listSync(recursive: true)) {
          consider(entity.statSync().modified);
        }
      default:
    }
  }
  return newest;
}

DateTime? _modified(String path) {
  final file = fs.file(path);
  return file.existsSync() ? file.statSync().modified : null;
}
