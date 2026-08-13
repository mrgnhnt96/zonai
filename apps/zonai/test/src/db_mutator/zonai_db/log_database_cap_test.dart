import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:resqlite/resqlite.dart' as rs;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// `logDatabaseMaxSize` — the opt-in ceiling on the log database file.
///
/// Only expressible because `_log` has a file of its own: `max_page_count`
/// bounds a *file*, so on the shared database the ceiling would be hit by
/// whichever write arrived first, application inserts included. That is the
/// property these tests are really guarding, so both halves are asserted —
/// log writes stop, application writes do not.
void main() {
  setUpAll(() {
    final lib = io.File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  late io.Directory projectRoot;

  setUp(() async {
    projectRoot = await io.Directory.systemTemp.createTemp('zonai_log_cap_');
    io.Directory(
      '${projectRoot.path}/.zonai/migrations',
    ).createSync(recursive: true);
  });

  tearDown(() async {
    if (projectRoot.existsSync()) projectRoot.deleteSync(recursive: true);
  });

  Future<Settings> settingsWith(String yaml) async {
    io.File('${projectRoot.path}/zonai.yaml').writeAsStringSync(yaml);
    return runMergedScopedFuture(
      () async => Settings.load(projectRoot.path),
      override: {fsProvider.overrideWith(LocalFileSystem.new)},
    );
  }

  Future<T> withScope<T>(Settings settings, Future<T> Function() body) =>
      runMergedScopedFuture(
        body,
        override: {
          fsProvider.overrideWith(LocalFileSystem.new),
          loggerProvider.overrideWith(() => Logger(level: .error)),
          settingsProvider.overrideWith(() => settings),
          processProvider,
          cleanUpProvider,
          executableStopProvider,
          migrateProvider,
        },
      );

  test(
    'a configured cap stops log writes and leaves application writes alone',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      // Deliberately tiny so the ceiling is reachable in a test.
      final settings = await settingsWith(
        'name: test\nlogDatabaseMaxSize: 64kb\n',
      );

      await withScope(settings, () async {
        final zonaiDb = ZonaiDb();
        try {
          final db = await zonaiDb.open();
          await db.execute(
            'CREATE TABLE "main"."widgets" ("id" INTEGER PRIMARY KEY, "m" TEXT)',
          );

          final padding = 'x' * 2000;
          Object? logFailure;
          try {
            for (var i = 0; i < 500; i++) {
              await db.execute(
                'INSERT INTO "_log" ("id", "level", "message", "timestamp", '
                '"trace_id") VALUES (?, ?, ?, ?, ?)',
                ['id$i', 'info', padding, i, 't'],
              );
            }
          } catch (e) {
            logFailure = e;
          }

          expect(
            logFailure,
            isNotNull,
            reason: 'the cap must actually stop log writes, or it caps nothing',
          );
          expect('$logFailure'.toLowerCase(), contains('full'));

          // The half that makes a cap safe to offer at all.
          await db.execute('INSERT INTO "main"."widgets" ("m") VALUES (?)', [
            padding,
          ]);
          final widgets = await db.execute(
            'SELECT COUNT(*) FROM "main"."widgets"',
          );
          expect(
            widgets.rows.single.single,
            1,
            reason:
                'a cap on the shared file would have failed this too, which '
                'is exactly why it could not land before the split',
          );
        } finally {
          await zonaiDb.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'no cap is applied when the setting is absent -- the default is unlimited',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      final settings = await settingsWith('name: test\n');
      expect(settings.logDatabaseMaxBytes, isNull);

      await withScope(settings, () async {
        final zonaiDb = ZonaiDb();
        try {
          final db = await zonaiDb.open();
          final padding = 'x' * 2000;
          // Comfortably past the 64kb the capped case died at.
          for (var i = 0; i < 500; i++) {
            await db.execute(
              'INSERT INTO "_log" ("id", "level", "message", "timestamp", '
              '"trace_id") VALUES (?, ?, ?, ?, ?)',
              ['id$i', 'info', padding, i, 't'],
            );
          }

          final rows = await db.execute('SELECT COUNT(*) FROM "_log"');
          expect(rows.rows.single.single, 500);
        } finally {
          await zonaiDb.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('removing the setting lifts the cap on the next open, with nothing to '
      'reset', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    // `max_page_count` is per-connection and not persisted -- measured, and
    // the reason there is no "uncap" path to maintain. If it ever became a
    // stored property, a database that once had a cap would keep it after
    // the operator removed the setting, with no way to tell why writes were
    // still failing.
    final capped = await settingsWith('name: test\nlogDatabaseMaxSize: 64kb\n');
    await withScope(capped, () async {
      final zonaiDb = ZonaiDb();
      try {
        final db = await zonaiDb.open();
        final padding = 'x' * 2000;
        try {
          for (var i = 0; i < 500; i++) {
            await db.execute(
              'INSERT INTO "_log" ("id", "level", "message", "timestamp", '
              '"trace_id") VALUES (?, ?, ?, ?, ?)',
              ['id$i', 'info', padding, i, 't'],
            );
          }
        } catch (_) {
          // Expected: this is the run that hits the ceiling.
        }
      } finally {
        await zonaiDb.dispose();
      }
    });

    final uncapped = await settingsWith('name: test\n');
    await withScope(uncapped, () async {
      final zonaiDb = ZonaiDb();
      try {
        final db = await zonaiDb.open();
        final before = await db.execute('SELECT COUNT(*) FROM "_log"');
        await db.execute(
          'INSERT INTO "_log" ("id", "level", "message", "timestamp", '
          '"trace_id") VALUES (?, ?, ?, ?, ?)',
          ['after-uncap', 'info', 'x' * 2000, 1, 't'],
        );
        final after = await db.execute('SELECT COUNT(*) FROM "_log"');
        expect(
          after.rows.single.single,
          (before.rows.single.single! as int) + 1,
          reason: 'the write that was refused a moment ago must now land',
        );
      } finally {
        await zonaiDb.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('an unparseable size is refused rather than silently ignored', () async {
    // Falling back to unlimited would leave an operator believing they had a
    // ceiling they do not have -- which is one instance of the exact failure
    // this feature exists to prevent.
    await expectLater(
      () => settingsWith('name: test\nlogDatabaseMaxSize: 512 megabytes\n'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      () => settingsWith('name: test\nlogDatabaseMaxSize: 0\n'),
      throwsA(isA<FormatException>()),
    );
  });
}
