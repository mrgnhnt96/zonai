import 'dart:io' as io;

import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/commands/compile.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/config.dart';
import 'package:zonai/src/deps/crons.dart';
import 'package:zonai/src/deps/env.dart';
import 'package:zonai/src/deps/executable_stop.dart';
import 'package:zonai/src/deps/extensions.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/operations.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/rate_limits.dart';
import 'package:zonai/src/deps/rules.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/config/config.dart';
import 'package:zonai/src/domain/cron/crons.dart';
import 'package:zonai/src/domain/extensions/extensions.dart';
import 'package:zonai/src/domain/operations/operations.dart';
import 'package:zonai/src/domain/process.dart';
import 'package:zonai/src/domain/rate_limit/rate_limits.dart';
import 'package:zonai/src/domain/rules/rules.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// The six workers, in the order `compile` fans them out, paired with the
/// generated entrypoint each one hands to `dart compile exe`. Keying the fake
/// process off the entrypoint is what lets a single run fail some workers and
/// not others.
const _workers = {
  'operations': 'db_operations.dart',
  'extensions': 'db_extensions.dart',
  'rules': 'db_rules.dart',
  'rate limits': 'db_rate_limit.dart',
  'crons': 'db_crons.dart',
  'config': 'db_config.dart',
};

void main() {
  late MemoryFileSystem fileSystem;
  late _FakeProcess process;
  late _RecordingLogger logger;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    process = _FakeProcess();
    logger = _RecordingLogger();

    // Every worker needs its source directory to exist, or the compilers take
    // their "nothing here" shortcut and never reach the code under test:
    // `_analyze` returns 0 for an absent directory, and `Config._canCompile`
    // skips the compile entirely.
    for (final path in [
      _settings.operationsPath,
      _settings.extensionsPath,
      _settings.rulesPath,
      _settings.rateLimitPath,
      _settings.cronsPath,
      _settings.configPath,
      _settings.schemasPath,
    ]) {
      fileSystem.directory(path).createSync(recursive: true);
    }
    // Config has no `dart analyze` step; it decides there is work to do by
    // finding at least one Dart file.
    fileSystem
        .file(fileSystem.path.join(_settings.configPath, 'app_config.dart'))
        .writeAsStringSync('// config\n');
  });

  /// Runs the real `zonai compile` fan-out against the fakes above.
  ///
  /// No `buildSettings`, i.e. the bare `zonai compile` path, so the host
  /// rebuild is reached too -- it no-ops here because the memory filesystem
  /// has no host binary on it.
  Future<int> runCompile() => runScoped(
    () => compile(),
    values: {
      fsProvider.overrideWith(() => fileSystem),
      settingsProvider.overrideWith(() => _settings),
      processProvider.overrideWith(() => process),
      loggerProvider.overrideWith(() => logger),
      argsProvider.overrideWith(() => const Args()),
      operationsProvider.overrideWith(Operations.new),
      extensionsProvider.overrideWith(Extensions.new),
      rulesProvider.overrideWith(Rules.new),
      rateLimitsProvider.overrideWith(RateLimitsCompiler.new),
      cronsProvider.overrideWith(CronsCompiler.new),
      configProvider.overrideWith(Config.new),
      executableStopProvider,
      cleanUpProvider,
      envProvider,
    },
  );

  test('exits 0 when all six workers compile cleanly', () async {
    expect(await runCompile(), 0);
    expect(
      logger.errors,
      isEmpty,
      reason: 'a clean run should report no failures',
    );
  });

  test('exits non-zero when a worker fails `dart analyze`', () async {
    process.analyzeExitCodes[_settings.rulesPath] = 3;

    expect(
      await runCompile(),
      3,
      reason: "the analyzer's own exit code should reach the shell",
    );
    expect(logger.errors, contains(contains('Failed to compile: rules')));
  });

  test('exits non-zero when a worker fails `dart compile exe`', () async {
    process.compileExitCodes['db_crons.dart'] = 254;

    expect(
      await runCompile(),
      254,
      reason: "the compiler's own exit code should reach the shell",
    );
    expect(logger.errors, contains(contains('Failed to compile: crons')));
  });

  // The whole point of keeping the `Future.wait` fan-out: fixing six broken
  // workers should cost one `zonai compile`, not six.
  test('names every failing worker, not just the first', () async {
    process.analyzeExitCodes[_settings.operationsPath] = 2;
    process.compileExitCodes['db_extensions.dart'] = 5;
    process.compileExitCodes['db_config.dart'] = 7;

    final exitCode = await runCompile();

    expect(
      exitCode,
      2,
      reason: 'the first failure in fan-out order, so the code is stable',
    );

    final summary = logger.errors.singleWhere(
      (line) => line.startsWith('Failed to compile:'),
      orElse: () => fail('no summary line in ${logger.errors}'),
    );
    expect(summary, contains('operations'));
    expect(summary, contains('extensions'));
    expect(summary, contains('config'));
    expect(summary, isNot(contains('rules')));
    expect(summary, isNot(contains('crons')));
  });

  test('a worker that fails does not overwrite its previous executable', () {
    // Guards the knock-on the exit code exists to stop: the compilers return
    // before writing `target`, so a stale binary survives a failed compile and
    // `zonai build` would otherwise bundle it while exiting 0.
    // `compiledCronsPath` derives from `fs`, so it has to be asked for
    // inside a scope that has one.
    final cronsPath = runScoped(
      () => _settings.compiledCronsPath,
      values: {fsProvider.overrideWith(() => fileSystem)},
    );
    final stale = fileSystem.file(cronsPath)
      ..createSync(recursive: true)
      ..writeAsStringSync('stale binary');
    process.compileExitCodes['db_crons.dart'] = 1;

    expect(
      runCompile(),
      completion(isNot(0)),
      reason: 'the stale executable must not be shipped silently',
    );
    expect(stale.readAsStringSync(), 'stale binary');
  });

  test('an AOT snapshot failure warns but does not fail the command', () async {
    // Deliberate, and documented in operations.dart/rules.dart: the snapshot
    // is only the isolate transport's fast path, and without it the runtime
    // falls back to spawning the .exe that did compile.
    process.snapshotExitCode = 1;

    expect(await runCompile(), 0);
    expect(
      logger.warnings.where((line) => line.contains('AOT snapshot')),
      isNotEmpty,
      reason: 'the fallback should still be visible',
    );
    expect(logger.errors, isEmpty);
  });
}

final _settings = Settings(
  path: 'zonai.yaml',
  migrationsPath: '.zonai/migrations',
  dataPath: '.zonai/data',
  schemasPath: 'lib/src/schemas',
  extensionsPath: 'lib/src/extensions',
  rulesPath: 'lib/src/rules',
  operationsPath: 'lib/src/operations',
  configPath: 'lib/src/config',
  rateLimitPath: 'lib/src/rate_limit',
  cronsPath: 'lib/src/crons',
  emailTemplatesPath: 'lib/src/email_templates',
  imagesPath: 'lib/src/images',
  buildSettings: BuildSettings.current(),
  version: kVersion,
);

/// A [Process] that answers `dart analyze` / `dart compile` without running
/// anything, with the exit code of each keyed by what is being compiled.
class _FakeProcess extends Process {
  /// Keyed by the directory handed to `dart analyze`; absent means clean.
  final analyzeExitCodes = <String, int>{};

  /// Keyed by the generated entrypoint's basename (see [_workers]); absent
  /// means the compile succeeds.
  final compileExitCodes = <String, int>{};

  /// Shared by every worker's `dart compile aot-snapshot`.
  int snapshotExitCode = 0;

  @override
  Future<io.ProcessResult> runDart(List<String> arguments) async {
    final exitCode = switch (arguments) {
      ['analyze', final directory, ...] => analyzeExitCodes[directory] ?? 0,
      ['compile', 'aot-snapshot', ...] => snapshotExitCode,
      ['compile', 'exe', ...] => compileExitCodes[_entrypoint(arguments)] ?? 0,
      _ => 0,
    };

    return io.ProcessResult(0, exitCode, '', exitCode == 0 ? '' : 'boom');
  }

  /// The `db_*.dart` this invocation is compiling.
  String _entrypoint(List<String> arguments) => arguments
      .firstWhere(
        (argument) => _workers.values.any(argument.endsWith),
        orElse: () => fail('no known entrypoint in $arguments'),
      )
      .split(RegExp(r'[/\\]'))
      .last;
}

/// Captures the levels the summary line has to be distinguishable by.
class _RecordingLogger extends Logger {
  final errors = <String>[];
  final warnings = <String>[];

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      errors.add(message);

  @override
  void warn(String message, {String? prefix}) => warnings.add(message);

  @override
  void info(String message) {}

  @override
  void debug(String message, {String? prefix}) {}
}
