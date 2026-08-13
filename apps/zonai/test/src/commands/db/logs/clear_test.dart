import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/db/logs/clear.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../admin/fake_zonai_db.dart';

// Issue #28's real database was 852,811,776 bytes before and 1,101,824 after.
// These keep the same shape two orders of magnitude down: MemoryFileSystem
// holds the bytes in RAM, so seeding the true figures cost seconds per test
// for nothing -- formatBytes has its own unit tests for the boundaries.
const _bigDb = 9000000; // 9.0 MB
const _smallDb = 1100000; // 1.1 MB

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

/// Runs the command against an in-memory filesystem holding a database file
/// of [dbSizeBytes], so the reclaim arithmetic has something real to measure.
Future<({int exitCode, String output, List<String> prompts})> _run(
  Args args, {
  required FakeZonaiDb db,
  int dbSizeBytes = 0,
  bool answerPrompt = true,
  int? dbSizeAfterVacuum,
}) async {
  final sink = _CapturingSink();
  final memoryFs = MemoryFileSystem();
  final prompts = <String>[];

  // `zonaiSqlitePath` resolves through the scoped `fs`, so it has to be read
  // inside a scope rather than off `fakeSettings` directly.
  final dbPath = runScoped(
    () => fakeSettings.zonaiSqlitePath,
    values: {fsProvider.overrideWith(() => memoryFs)},
  );

  if (dbSizeBytes > 0) {
    memoryFs.file(dbPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(dbSizeBytes, 0));
  }

  // The real `vacuum()` shrinks the file; the fake cannot, so shrink it here
  // at the moment it is called to keep the reported delta honest.
  if (dbSizeAfterVacuum != null) {
    db.onVacuum = () => memoryFs
        .file(dbPath)
        .writeAsBytesSync(List.filled(dbSizeAfterVacuum, 0));
  }

  final exitCode = await runScoped(
    () => clearLogs(
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
            () => db,
      ),
    },
  );

  return (exitCode: exitCode, output: sink.text, prompts: prompts);
}

void main() {
  group('clearLogs', () {
    test('prints usage and does nothing for --help', () async {
      final db = newFakeZonaiDb();
      final result = await _run(Args(args: {'help': true}), db: db);

      expect(result.exitCode, 1);
      expect(result.output, contains('zonai db logs clear'));
      expect(db.clearLogsCall, isNull);
    });

    test('deletes every record when no cutoff is given', () async {
      final db = newFakeZonaiDb()..clearLogsResult = 3803015;
      final result = await _run(Args(args: {}), db: db, dbSizeBytes: 1000);

      expect(result.exitCode, 0);
      expect(db.clearLogsCall, isNotNull);
      expect(db.clearLogsCall!.before, isNull);
      expect(result.output, contains('Cleared 3803015 log records'));
    });

    test('singularizes the count for one record', () async {
      final db = newFakeZonaiDb()..clearLogsResult = 1;
      final result = await _run(Args(args: {}), db: db);

      expect(result.output, contains('Cleared 1 log record'));
      expect(result.output, isNot(contains('1 log records')));
    });

    group('without --vacuum', () {
      test('warns that the freed space is still allocated on disk', () async {
        final db = newFakeZonaiDb()..clearLogsResult = 3803015;
        final result = await _run(
          Args(args: {}),
          db: db,
          dbSizeBytes: _bigDb,
        );

        expect(db.vacuumCalled, isFalse);
        expect(
          result.output,
          contains('9.0 MB is still allocated on disk'),
          reason:
              'issue #28: a silent no-op on disk is the misleading part -- '
              'clear must say the space was not returned',
        );
        expect(result.output, contains('--vacuum'));
      });

      test('stays quiet about disk when nothing was deleted', () async {
        final db = newFakeZonaiDb()..clearLogsResult = 0;
        final result = await _run(
          Args(args: {}),
          db: db,
          dbSizeBytes: _bigDb,
        );

        expect(result.output, contains('Cleared 0 log records'));
        expect(
          result.output,
          isNot(contains('still allocated')),
          reason: 'no rows deleted means no space was left behind to reclaim',
        );
      });
    });

    group('--older-than', () {
      test('passes a cutoff computed back from now', () async {
        final now = DateTime.utc(2026, 8, 12, 9);
        final db = newFakeZonaiDb()..clearLogsResult = 42;

        await withClock(Clock.fixed(now), () async {
          final result = await _run(Args(args: {'older-than': '7d'}), db: db);
          expect(result.exitCode, 0);
        });

        expect(db.clearLogsCall!.before, now.subtract(const Duration(days: 7)));
      });

      test('accepts hours, minutes and weeks', () async {
        final now = DateTime.utc(2026, 8, 12, 9);

        for (final (input, expected) in [
          ('24h', Duration(hours: 24)),
          ('30m', Duration(minutes: 30)),
          ('2w', Duration(days: 14)),
        ]) {
          final db = newFakeZonaiDb();
          await withClock(Clock.fixed(now), () async {
            await _run(Args(args: {'older-than': input}), db: db);
          });
          expect(
            db.clearLogsCall!.before,
            now.subtract(expected),
            reason: 'for --older-than $input',
          );
        }
      });

      test('rejects an unparseable age without deleting anything', () async {
        final db = newFakeZonaiDb();
        final result = await _run(
          Args(args: {'older-than': 'last tuesday'}),
          db: db,
        );

        expect(result.exitCode, 1);
        expect(result.output, contains('Invalid --older-than'));
        expect(
          db.clearLogsCall,
          isNull,
          reason: 'a misread age must not fall back to deleting everything',
        );
      });

      test('rejects a bare number with no unit', () async {
        final db = newFakeZonaiDb();
        final result = await _run(Args(args: {'older-than': 7}), db: db);

        expect(result.exitCode, 1);
        expect(db.clearLogsCall, isNull);
      });
    });

    group('--vacuum', () {
      test('requires confirmation and reports what was reclaimed', () async {
        final db = newFakeZonaiDb()..clearLogsResult = 3803015;
        final result = await _run(
          Args(args: {'vacuum': true}),
          db: db,
          dbSizeBytes: _bigDb,
          dbSizeAfterVacuum: _smallDb,
        );

        expect(result.exitCode, 0);
        expect(result.prompts, hasLength(1));
        expect(db.vacuumCalled, isTrue);
        // Both files, not just the log one. `_log` lives in its own database
        // now, but a deployment upgraded from before the split has just had a
        // multi-million-row `_log` dropped out of `main`, and those pages are
        // on *main's* freelist -- vacuuming only the log file would reclaim
        // nothing at all for exactly the case this command exists to rescue.
        expect(db.vacuumedSchemas, [null, kLogDbSchema]);
        expect(result.output, contains('Reclaimed 7.9 MB'));
        expect(result.output, contains('9.0 MB -> 1.1 MB'));
      });

      test('explains the cost before asking', () async {
        final db = newFakeZonaiDb();
        final result = await _run(
          Args(args: {'vacuum': true}),
          db: db,
          dbSizeBytes: _bigDb,
        );

        final prompt = result.prompts.single;
        expect(prompt, contains('rewrites the entire database file'));
        expect(prompt, contains('9.0 MB'));
        expect(prompt, contains('18.0 MB'), reason: 'needs room for a copy');
        expect(prompt, contains('locked'));
        expect(prompt, contains('[y/N]'));
      });

      test('declining cancels the whole command, deleting nothing', () async {
        final db = newFakeZonaiDb()..clearLogsResult = 3803015;
        final result = await _run(
          Args(args: {'vacuum': true}),
          db: db,
          dbSizeBytes: _bigDb,
          answerPrompt: false,
        );

        expect(result.exitCode, 0);
        expect(result.output, contains('Cancelled.'));
        expect(
          db.clearLogsCall,
          isNull,
          reason: 'the prompt says answering no deletes nothing either',
        );
        expect(db.vacuumCalled, isFalse);
      });

      test('--force skips the prompt entirely', () async {
        final db = newFakeZonaiDb()..clearLogsResult = 10;
        final result = await _run(
          Args(args: {'vacuum': true, 'force': true}),
          db: db,
          dbSizeBytes: 1000,
        );

        expect(result.prompts, isEmpty);
        expect(db.vacuumCalled, isTrue);
        expect(result.exitCode, 0);
      });

      test('-f skips the prompt too', () async {
        final db = newFakeZonaiDb()..clearLogsResult = 10;
        final result = await _run(
          Args(args: {'vacuum': true}, abbr: {'f': true}),
          db: db,
          dbSizeBytes: 1000,
        );

        expect(
          result.prompts,
          isEmpty,
          reason: '-f is parsed into abbrs, not values',
        );
        expect(db.vacuumCalled, isTrue);
      });

      test('does not print the still-allocated hint', () async {
        final db = newFakeZonaiDb()..clearLogsResult = 5;
        final result = await _run(
          Args(args: {'vacuum': true, 'force': true}),
          db: db,
          dbSizeBytes: _bigDb,
          dbSizeAfterVacuum: _smallDb,
        );

        expect(result.output, isNot(contains('still allocated')));
      });

      test('combines with --older-than', () async {
        final now = DateTime.utc(2026, 8, 12, 9);
        final db = newFakeZonaiDb()..clearLogsResult = 100;

        await withClock(Clock.fixed(now), () async {
          await _run(
            Args(args: {'vacuum': true, 'force': true, 'older-than': '7d'}),
            db: db,
            dbSizeBytes: 1000,
          );
        });

        expect(db.clearLogsCall!.before, now.subtract(const Duration(days: 7)));
        expect(db.vacuumCalled, isTrue);
      });
    });

    test('reports a failure without crashing', () async {
      final db = newFakeZonaiDb()..clearLogsError = StateError('disk full');
      final result = await _run(Args(args: {}), db: db);

      expect(result.exitCode, 1);
      expect(result.output, contains('Failed to clear logs'));
    });
  });
}
