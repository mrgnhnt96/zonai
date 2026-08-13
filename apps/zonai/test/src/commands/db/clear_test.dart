import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/db/clear.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

import 'admin/fake_zonai_db.dart';

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

Future<({int exitCode, String output, List<String> prompts, bool dbExists})>
_run(Args args, {bool seedDatabase = true, bool answerPrompt = true}) async {
  final sink = _CapturingSink();
  final memoryFs = MemoryFileSystem();
  final prompts = <String>[];

  final dbPath = runScoped(
    () => fakeSettings.zonaiSqlitePath,
    values: {fsProvider.overrideWith(() => memoryFs)},
  );

  if (seedDatabase) {
    for (final path in [dbPath, '$dbPath-wal', '$dbPath-shm']) {
      memoryFs.file(path)
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
    }
  }

  final exitCode = await runScoped(
    () => clearDatabase(
      confirm: (question) {
        prompts.add(question);
        return answerPrompt;
      },
    ),
    values: {
      argsProvider.overrideWith(() => args),
      loggerProvider.overrideWith(
        () => Logger(level: .info, stdout: IOSink(sink), stderr: IOSink(sink)),
      ),
      settingsProvider.overrideWith(() => fakeSettings),
      fsProvider.overrideWith(() => memoryFs),
      zonaiDbProvider.overrideWith(
        () =>
            () => newFakeZonaiDb(),
      ),
    },
  );

  return (
    exitCode: exitCode,
    output: sink.text,
    prompts: prompts,
    dbExists: memoryFs.file(dbPath).existsSync(),
  );
}

void main() {
  group('clearDatabase', () {
    test('prints usage and deletes nothing for --help', () async {
      final result = await _run(Args(args: {'help': true}));

      expect(result.exitCode, 1);
      expect(result.output, contains('zonai db clear'));
      expect(result.prompts, isEmpty);
      expect(result.dbExists, isTrue);
    });

    test('prompts before deleting when --yes is absent', () async {
      final result = await _run(Args(args: {}));

      expect(result.prompts, hasLength(1));
      expect(result.prompts.single, contains('[y/N]'));
      expect(result.dbExists, isFalse);
    });

    test('declining keeps the database', () async {
      final result = await _run(Args(args: {}), answerPrompt: false);

      expect(result.exitCode, 0);
      expect(result.output, contains('Cancelled.'));
      expect(result.dbExists, isTrue);
    });

    test('--yes skips the prompt', () async {
      final result = await _run(Args(args: {'yes': true}));

      expect(result.prompts, isEmpty);
      expect(result.dbExists, isFalse);
    });

    test('-y skips the prompt too', () async {
      final result = await _run(Args(abbr: {'y': true}));

      expect(
        result.prompts,
        isEmpty,
        reason:
            '-y is parsed into abbrs, not values, so reading it as '
            "args['y'] silently prompted anyway",
      );
      expect(result.dbExists, isFalse);
    });

    test('deletes the WAL sidecars alongside the database', () async {
      final result = await _run(Args(args: {'yes': true}));

      expect(result.output, contains('zonai.sqlite-wal'));
      expect(result.output, contains('zonai.sqlite-shm'));
    });

    test('says nothing to delete when there is no database', () async {
      final result = await _run(Args(args: {}), seedDatabase: false);

      expect(result.exitCode, 0);
      expect(result.output, contains('No database file found'));
      expect(result.prompts, isEmpty);
    });
  });
}
