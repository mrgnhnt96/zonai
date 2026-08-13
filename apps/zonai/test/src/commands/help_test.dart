import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/ai/ai.dart';
import 'package:zonai/src/commands/build.dart';
import 'package:zonai/src/commands/compile.dart';
import 'package:zonai/src/commands/db/db.dart';
import 'package:zonai/src/commands/db/photos.dart';
import 'package:zonai/src/commands/db/test.dart' as db_smoke_test;
import 'package:zonai/src/commands/dev/dev.dart';
import 'package:zonai/src/commands/migrate/migrate.dart';
import 'package:zonai/src/commands/ping.dart';
import 'package:zonai/src/commands/rules.dart';
import 'package:zonai/src/commands/serve.dart';
import 'package:zonai/src/commands/version.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// Every command's `--help` must print its usage and return *before* it
/// touches anything else.
///
/// The scope below deliberately registers only `args` and `logger`. Any
/// command that reaches past its help check for the filesystem, settings, the
/// database, a worker, or a subprocess fails here by throwing on an
/// unregistered provider rather than by quietly starting a server -- which is
/// exactly how `serve --help` used to behave: it booted, swept crons, and
/// applied a pending migration to whatever database the working directory
/// resolved to.
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

Future<({int exitCode, String output})> _help(
  Future<int> Function() command, {
  Args? args,
}) async {
  final sink = _CapturingSink();

  final exitCode = await runScoped(
    command,
    values: {
      argsProvider.overrideWith(() => args ?? Args(args: {'help': true})),
      loggerProvider.overrideWith(
        () => Logger(level: .info, stdout: IOSink(sink), stderr: IOSink(sink)),
      ),
    },
  );

  return (exitCode: exitCode, output: sink.text);
}

void main() {
  group('--help prints usage without doing the work', () {
    test('serve', () async {
      final result = await _help(serve);

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai serve'));
      expect(result.output, contains('--no-auto-migrate'));
    });

    test('dev', () async {
      final result = await _help(dev);

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai dev'));
    });

    test('compile', () async {
      final result = await _help(compile);

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai compile'));
    });

    test('ping', () async {
      final result = await _help(ping);

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai ping'));
    });

    test('build', () async {
      final result = await _help(build);

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai build'));
    });

    test('version', () async {
      final result = await _help(() => version(const []));

      expect(result.output, contains('Usage: zonai version'));
    });

    test('db', () async {
      final result = await _help(() => db(const []));

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai db'));
    });

    test('db test', () async {
      final result = await _help(db_smoke_test.test);

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai db test'));
    });

    test('db photos', () async {
      final result = await _help(photos);

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai db photos'));
    });

    test('db migrate', () async {
      final result = await _help(() => migrate(const []));

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai db migrate'));
    });

    test('db migrate generate', () async {
      final result = await _help(() => migrate(const ['generate']));

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai db migrate generate'));
    });

    test('db migrate apply', () async {
      final result = await _help(() => migrate(const ['apply']));

      expect(
        result.exitCode,
        1,
        reason: 'this used to apply the pending migrations and report success',
      );
      expect(result.output, contains('Usage: zonai db migrate apply'));
    });

    test('rules', () async {
      final result = await _help(() => rules(const []));

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai rules'));
    });

    test('rules list', () async {
      final result = await _help(() => rules(const ['list']));

      expect(
        result.exitCode,
        1,
        reason: 'a subcommand used to make the help flag be ignored entirely',
      );
      expect(result.output, contains('Usage: zonai rules'));
    });

    test('rules table', () async {
      final result = await _help(() => rules(const ['table', 'items', 'read']));

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai rules'));
    });

    test('ai', () async {
      final result = await _help(() => ai(const []));

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai ai'));
    });

    for (final tool in const [
      'all',
      'claude',
      'cursor',
      'copilot',
      'windsurf',
      'cline',
    ]) {
      test('ai $tool', () async {
        final result = await _help(() => ai([tool]));

        expect(
          result.exitCode,
          1,
          reason: '`zonai ai $tool --help` used to write the files',
        );
        expect(result.output, contains('Usage: zonai ai'));
      });
    }

    test('-h is honored as well as --help', () async {
      final result = await _help(serve, args: Args(abbr: {'h': true}));

      expect(result.exitCode, 1);
      expect(result.output, contains('Usage: zonai serve'));
    });
  });
}
