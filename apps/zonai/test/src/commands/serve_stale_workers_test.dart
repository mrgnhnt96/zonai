import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/commands/serve.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/env.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// `zonai serve --release` refuses to start when a worker is older than its
/// sources, instead of serving the old build.
///
/// Reported against v0.10.1: a row rule's `canDelete` changed to `true`, and
/// a fresh `zonai serve --release` still answered "Access denied: action
/// delete" until `zonai compile`. A warning would scroll past in a service
/// log while the server enforced yesterday's policy, so this is an exit.
///
/// Like `serve_insecure_test_mode_test.dart`, the scope registers only what
/// the refusal needs. A `serve()` that got past it would throw on an
/// unregistered provider rather than start a server, so the absence of the
/// check cannot make the exit-code assertion pass with the right message.
class _CapturingSink implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.forEach(bytes.addAll);
  }

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}

void main() {
  late MemoryFileSystem memoryFs;
  final now = DateTime.now();

  setUp(() {
    memoryFs = MemoryFileSystem();
    memoryFs.currentDirectory = memoryFs.directory('/project')
      ..createSync(recursive: true);
    memoryFs.file('zonai.yml').createSync();
  });

  void write(String path, DateTime modified) {
    memoryFs.file(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('// $path')
      ..setLastModifiedSync(modified);
  }

  Future<({int exitCode, String output})> serveRelease() async {
    final sink = _CapturingSink();
    final exitCode = await runScoped(
      serve,
      values: {
        argsProvider.overrideWith(() => Args(args: const {'release': true})),
        loggerProvider.overrideWith(
          () =>
              Logger(level: .info, stdout: IOSink(sink), stderr: IOSink(sink)),
        ),
        fsProvider.overrideWith(() => memoryFs),
        envProvider,
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
    return (exitCode: exitCode, output: sink.text);
  }

  test('a rule edited after the last compile stops --release', () async {
    write('.zonai/executables/db_rules.exe', now);
    write(
      'lib/src/rules/posts_row_rules.dart',
      now.add(const Duration(minutes: 5)),
    );

    final result = await serveRelease();

    expect(result.exitCode, isNot(0));
    expect(result.output, contains('rules'));
    expect(result.output, contains('zonai compile'));
  });
}
