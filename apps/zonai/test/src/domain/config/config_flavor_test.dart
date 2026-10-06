import 'dart:io' as io;

import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/env.dart';
import 'package:zonai/src/deps/executable_stop.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/config/config.dart';
import 'package:zonai/src/domain/process.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// A helper file beside the config made `zonai build --flavor prod` fail with
/// "No config file found for flavor prod", and then a second error, ".dart_tool/
/// zonai/db_config.dart file not found", from compiling an entry point that
/// was never written (reported against v0.10.1, with
/// `lib/src/config/email_env.dart` next to the config). Neither said that the
/// helper was the problem.
class _RecordingProcess extends Process {
  final calls = <List<String>>[];

  @override
  Future<io.ProcessResult> runDart(List<String> arguments) async {
    calls.add(arguments);
    return io.ProcessResult(0, 0, '', '');
  }
}

void main() {
  late MemoryFileSystem memoryFs;
  late _RecordingProcess recorder;
  late List<String> logs;

  setUp(() {
    memoryFs = MemoryFileSystem();
    memoryFs.currentDirectory = memoryFs.directory('/project')
      ..createSync(recursive: true);
    recorder = _RecordingProcess();
    logs = [];
  });

  void write(String path) => memoryFs.file(path)
    ..createSync(recursive: true)
    ..writeAsStringSync('// $path');

  Future<int> compileWithFlavor(String? flavor) => runScoped(
    () => Config().compile(),
    values: {
      argsProvider.overrideWith(() => Args(args: {'flavor': ?flavor})),
      fsProvider.overrideWith(() => memoryFs),
      processProvider.overrideWith(() => recorder),
      envProvider,
      executableStopProvider,
      loggerProvider.overrideWith(
        () => Logger(
          level: .info,
          stdout: CallbackSink(callback: (m) => logs.add('$m')),
          stderr: CallbackSink(callback: (m) => logs.add('$m')),
        ),
      ),
      settingsProvider.overrideWith(
        () => Settings(
          path: 'zonai.yml',
          migrationsPath: 'migrations',
          dataPath: 'data',
          schemasPath: 'lib/src/schemas',
          extensionsPath: 'lib/src/extensions',
          rulesPath: 'lib/src/rules',
          operationsPath: 'lib/src/operations',
          configPath: 'lib/src/config',
          emailTemplatesPath: 'email_templates',
          rateLimitPath: 'lib/src/rate_limit',
          cronsPath: 'lib/src/crons',
          imagesPath: 'images',
          buildSettings: BuildSettings.current(),
          version: kVersion,
        ),
      ),
    },
  );

  group('a helper beside the config', () {
    setUp(() {
      write('lib/src/config/db_config.dart');
      write('lib/src/config/email_env.dart');
    });

    test('--flavor prod names the helper, its flavor, and the rule', () async {
      final exitCode = await compileWithFlavor('prod');

      expect(exitCode, isNot(0));
      final output = logs.join('\n');
      expect(output, contains('No config file found for flavor "prod"'));
      expect(output, contains('email_env.dart (flavor "email_env")'));
      expect(output, contains('db_config.dart (flavor "db_config")'));
      expect(output, contains('Move helpers that are not configs out of'));
    });

    test('nothing is compiled after the refusal', () async {
      await compileWithFlavor('prod');

      expect(
        recorder.calls,
        isEmpty,
        reason:
            'compiling the entry point that was never written is what '
            'produced the second, misleading "file not found" error',
      );
    });

    test('with no --flavor, the same explanation', () async {
      final exitCode = await compileWithFlavor(null);

      expect(exitCode, isNot(0));
      expect(logs.join('\n'), contains('Move helpers that are not configs'));
      expect(recorder.calls, isEmpty);
    });
  });

  test('a config named for the flavor still compiles', () async {
    write('lib/src/config/db_config.prod.dart');
    write('lib/src/config/db_config.dev.dart');

    final exitCode = await compileWithFlavor('prod');

    expect(exitCode, 0, reason: logs.join('\n'));
    expect(recorder.calls, isNotEmpty);
  });
}
