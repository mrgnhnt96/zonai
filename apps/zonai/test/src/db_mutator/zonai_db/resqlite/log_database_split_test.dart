import 'dart:async';
import 'dart:io';

import 'package:file/local.dart';
import 'package:resqlite/resqlite.dart' as rs;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/resqlite/resqlite_delegate.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// `_log` living in its own database file, end to end.
///
/// `attached_log_db_contract_test.dart` is the sibling of this file and pins
/// the SQLite/driver properties the split rests on -- including the one that
/// did *not* hold: a single `ATTACH` executed as a statement reaches only the
/// write connection, so log rows would be written and then be unreadable.
/// These tests cover the other half: that zonai actually holds up its end,
/// attaching on both connections at open and moving the table across.
void main() {
  setUpAll(() {
    final lib = File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  group('ResqliteDelegate.open(attach:)', () {
    late Directory dir;
    late ResqliteDelegate delegate;
    late Raindrop db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('zonai_log_attach_');
      delegate = await ResqliteDelegate.open(
        '${dir.path}/main.sqlite',
        attach: {kLogDbSchema: '${dir.path}/log.sqlite'},
      );
      db = Raindrop(delegate);
    });

    tearDown(() async {
      await delegate.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('a row written to the attached database can be read back through the '
        'delegate', () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await db.execute(
        'CREATE TABLE "$kLogDbSchema"."_log" '
        '("id" INTEGER PRIMARY KEY, "m" TEXT)',
      );
      await db.execute('INSERT INTO "_log" ("m") VALUES (?)', ['written']);

      // The property the contract test showed a statement-level ATTACH does
      // not give: the write lands on `rs.Database` and the read is answered
      // by the companion `package:sqlite3` handle, so both have to have been
      // attached at open. Reading it back is the *only* way to catch this --
      // the write half works either way, which is what makes the broken
      // version silent rather than loud.
      final read = await db.execute('SELECT "m" FROM "_log"');
      expect(read.rows.single.single, 'written');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'the row is in the log file, and `main` is left without a "_log" at all',
      () async {
        if (!rs.isInstalled) {
          markTestSkipped('resqlite native library not found');
          return;
        }

        await db.execute(
          'CREATE TABLE "$kLogDbSchema"."_log" '
          '("id" INTEGER PRIMARY KEY, "m" TEXT)',
        );
        await db.execute('INSERT INTO "_log" ("m") VALUES (?)', ['written']);

        final inMain = await db.execute(
          'SELECT 1 FROM "main".sqlite_master WHERE name = ?',
          ['_log'],
        );
        expect(
          inMain.rows,
          isEmpty,
          reason:
              'a schema-qualified CREATE must not also touch main -- if it '
              'did, the split would move nothing',
        );

        final direct = sqlite3.open('${dir.path}/log.sqlite');
        try {
          expect(
            direct.select('SELECT COUNT(*) AS c FROM "_log"').single['c'],
            1,
          );
        } finally {
          direct.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('a "_log" in main shadows the attached one -- which is why the move '
        'drops before it creates', () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await db.execute(
        'CREATE TABLE "$kLogDbSchema"."_log" '
        '("id" INTEGER PRIMARY KEY, "m" TEXT)',
      );
      await db.execute(
        'CREATE TABLE "main"."_log" ("id" INTEGER PRIMARY KEY, "m" TEXT)',
      );

      await db.execute('INSERT INTO "_log" ("m") VALUES (?)', ['shadowed']);

      final inMain = await db.execute('SELECT COUNT(*) FROM "main"."_log"');
      expect(
        inMain.rows.single.single,
        1,
        reason:
            'unqualified resolution prefers main, so leaving a stale _log '
            'there would send every log write straight back into the file '
            'the split exists to keep empty -- silently',
      );

      final inLog = await db.execute(
        'SELECT COUNT(*) FROM "$kLogDbSchema"."_log"',
      );
      expect(inLog.rows.single.single, 0);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the attached database is put into WAL mode -- it does not inherit '
        "main's", () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      // Measured, not assumed: an attached database keeps its own journal
      // mode and defaults to `delete` even when main is in WAL. That was
      // the state before this was set, and nothing anywhere errored --
      // `_purge`'s per-round `wal_checkpoint` and `_vacuum`'s trailing one
      // are simply no-ops against a database with no WAL. A silent no-op in
      // the two routines that exist to bound disk is worth a test.
      //
      // Read through `transaction`, which runs on the companion sqlite3
      // connection: `PRAGMA` is not a read verb, so `execute` routes it to
      // the writer, and the writer discards row data.
      for (final schema in ['main', kLogDbSchema]) {
        final mode = await delegate.transaction(
          (tx) => tx.execute('PRAGMA "$schema".journal_mode', const []),
        );
        expect(mode.rows.single.single, 'wal', reason: schema);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'a stream over a table in the attached database re-emits after a write',
      () async {
        if (!rs.isInstalled) {
          markTestSkipped('resqlite native library not found');
          return;
        }

        // The dashboard's live log view. Invalidation comes from resqlite's
        // writer reporting which tables a statement dirtied, and a table in an
        // attached database is the case that could plausibly report nothing --
        // in which case the view would render once and then quietly stop
        // updating, with no error anywhere.
        await db.execute(
          'CREATE TABLE "$kLogDbSchema"."_log" '
          '("id" INTEGER PRIMARY KEY, "m" TEXT)',
        );
        await db.execute('INSERT INTO "_log" ("m") VALUES (?)', ['first']);

        final emissions = <int>[];
        final second = Completer<void>();
        final sub = delegate
            .streamQuery('SELECT "m" FROM "_log" ORDER BY "id"', const [])
            .listen((result) {
              emissions.add(result.rows.length);
              if (emissions.length == 2 && !second.isCompleted) {
                second.complete();
              }
            });

        try {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          expect(emissions, [1]);

          await db.execute('INSERT INTO "_log" ("m") VALUES (?)', ['second']);

          await second.future.timeout(const Duration(seconds: 5));
          expect(emissions.last, 2);
        } finally {
          await sub.cancel();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('ZonaiDb.open', () {
    late Directory projectRoot;
    late Settings settings;

    setUp(() async {
      projectRoot = await Directory.systemTemp.createTemp('zonai_log_split_');
      // Present so `Settings.load` takes the file branch: without one it falls
      // through to reading `--config` off `args`, which is not in scope here.
      File('${projectRoot.path}/zonai.yaml').writeAsStringSync('name: test\n');
      // `Migrate.migrations()` throws rather than returning none when this is
      // absent, and `_openOnce` calls it on every open.
      Directory(
        '${projectRoot.path}/.zonai/migrations',
      ).createSync(recursive: true);
      settings = await runMergedScopedFuture(
        () async => Settings.load(projectRoot.path),
        override: {fsProvider.overrideWith(LocalFileSystem.new)},
      );
    });

    tearDown(() async {
      if (projectRoot.existsSync()) projectRoot.deleteSync(recursive: true);
    });

    /// Everything a [ZonaiDb] touches has to run inside this -- constructing
    /// one already reads `settings` (its mailman pools do), so the scope
    /// cannot start at [ZonaiDb.open].
    Future<T> withScope<T>(Future<T> Function() body) => runMergedScopedFuture(
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

    test('creates "_log" in its own file, with its indexes, and leaves none in '
        'main', () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      await withScope(() async {
        final zonaiDb = ZonaiDb();
        try {
          final db = await zonaiDb.open();

          final inMain = await db.execute(
            'SELECT 1 FROM "main".sqlite_master WHERE name = ?',
            ['_log'],
          );
          expect(inMain.rows, isEmpty);

          final inLog = await db.execute(
            'SELECT name FROM "$kLogDbSchema".sqlite_master '
            "WHERE type IN ('table', 'index') ORDER BY name",
          );
          expect(
            inLog.rows.map((r) => r.single).toList(),
            containsAll(['_log', 'log_id_unique', 'log_level_timestamp_index']),
            reason:
                'the indexes were created by a migration against main and '
                'dropped along with that table; without recreating them here '
                'every retention cutoff and dashboard query becomes a full '
                'scan of the one table that grows without bound',
          );
        } finally {
          await zonaiDb.dispose();
        }

        expect(
          File(settings.zonaiLogSqlitePath).existsSync(),
          isTrue,
          reason: 'the attached database must be a file of its own on disk',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'moves an existing main."_log" across, dropping its rows',
      () async {
        if (!rs.isInstalled) {
          markTestSkipped('resqlite native library not found');
          return;
        }

        await withScope(() async {
          // A database as it exists before the upgrade: `_log` in the shared
          // file, holding rows. Its columns are migration 0001's, so the
          // migrations that follow apply to it exactly as they would on a real
          // deployment -- plus `legacy_marker`, which no schema declares and
          // which is therefore how the assertions below tell the old table
          // apart from the new one.
          Directory(settings.dataPath).createSync(recursive: true);
          final seeded = await ResqliteDelegate.open(settings.zonaiSqlitePath);
          final seed = Raindrop(seeded);
          await seed.execute('''
CREATE TABLE "_log" (
  "error" TEXT,
  "id" TEXT PRIMARY KEY,
  "level" TEXT NOT NULL,
  "message" TEXT NOT NULL,
  "timestamp" INTEGER NOT NULL,
  "trace_id" TEXT NOT NULL,
  "legacy_marker" TEXT
)''');
          await seed.execute(
            'INSERT INTO "_log" ("id", "level", "message", "timestamp", '
            '"trace_id") VALUES (?, ?, ?, ?, ?)',
            ['a', 'info', 'old', 1, 't'],
          );
          await seeded.close();

          final zonaiDb = ZonaiDb();
          try {
            final db = await zonaiDb.open();

            final inMain = await db.execute(
              'SELECT 1 FROM "main".sqlite_master WHERE name = ?',
              ['_log'],
            );
            expect(
              inMain.rows,
              isEmpty,
              reason:
                  'the old table has to go, or it keeps shadowing the new one',
            );

            // Dropped, not migrated -- a deliberate decision. The deployments
            // that need this most hold millions of rows on a volume with no
            // room to copy anything, and the rows are logs.
            final rows = await db.execute('SELECT COUNT(*) FROM "_log"');
            expect(rows.rows.single.single, 0);

            // And the table that answered that query is genuinely the new
            // one, not an emptied version of the old: it carries the schema's
            // full current shape and none of the seed's `legacy_marker`.
            final columns = await db.execute(
              'SELECT name FROM pragma_table_info(?)',
              ['_log'],
            );
            final names = columns.rows.map((r) => r.single).toList();
            expect(names, containsAll(['props', 'is_admin', 'trace_id']));
            expect(names, isNot(contains('legacy_marker')));
          } finally {
            await zonaiDb.dispose();
          }
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'splits "_rate_limit" into its own file the same way',
      () async {
        if (!rs.isInstalled) {
          markTestSkipped('resqlite native library not found');
          return;
        }

        // The mechanism is shared, so this asserts the parts a second table
        // could get wrong independently: its own file, its own schema, and its
        // own index -- which the rate limiter depends on for *correctness*, not
        // just speed. It resolves the race between two concurrent requests
        // missing the same bucket row by retrying on constraint violation 19,
        // and without the unique index there is no violation to retry on.
        await withScope(() async {
          final zonaiDb = ZonaiDb();
          try {
            final db = await zonaiDb.open();

            final inMain = await db.execute(
              'SELECT 1 FROM "main".sqlite_master WHERE name = ?',
              ['_rate_limit'],
            );
            expect(inMain.rows, isEmpty);

            final inRateDb = await db.execute(
              'SELECT name FROM "$kRateLimitDbSchema".sqlite_master '
              "WHERE type IN ('table', 'index') ORDER BY name",
            );
            expect(
              inRateDb.rows.map((r) => r.single).toList(),
              containsAll(['_rate_limit', 'rate_limit_bucket_unique']),
            );

            await db.execute(
              'INSERT INTO "_rate_limit" ("id", "client_ip", "table", '
              '"operation", "count", "window_start") VALUES (?, ?, ?, ?, ?, ?)',
              ['a', '1.2.3.4', 'widgets', 'read', 1, 0],
            );
            await expectLater(
              db.execute(
                'INSERT INTO "_rate_limit" ("id", "client_ip", "table", '
                '"operation", "count", "window_start") VALUES (?, ?, ?, ?, ?, ?)',
                ['b', '1.2.3.4', 'widgets', 'read', 1, 0],
              ),
              throwsA(anything),
              reason:
                  'the bucket index has to be enforcing in the new file too -- '
                  "the rate limiter's duplicate-insert retry is what makes it "
                  'correct under concurrency',
            );
          } finally {
            await zonaiDb.dispose();
          }
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'opening twice is a no-op the second time',
      () async {
        if (!rs.isInstalled) {
          markTestSkipped('resqlite native library not found');
          return;
        }

        await withScope(() async {
          final first = ZonaiDb();
          try {
            final db = await first.open();
            await db.execute(
              'INSERT INTO "_log" ("id", "level", "message", "timestamp", '
              '"trace_id") VALUES (?, ?, ?, ?, ?)',
              ['a', 'info', 'kept', 1, 't'],
            );
          } finally {
            await first.dispose();
          }

          final second = ZonaiDb();
          try {
            final db = await second.open();
            final rows = await db.execute('SELECT "message" FROM "_log"');
            expect(
              rows.rows.single.single,
              'kept',
              reason:
                  'the move must not re-run once done, or every restart would '
                  'silently discard the logs since the last one',
            );
          } finally {
            await second.dispose();
          }
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
