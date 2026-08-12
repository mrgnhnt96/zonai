import 'dart:io';

import 'package:resqlite/resqlite.dart' as rs;
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/zonai_db/resqlite/resqlite_delegate.dart';
import 'package:zonai_schema/zonai_schema.dart';

// Issue #28: `zonai db logs clear` deleted 3,803,015 rows and the database
// file stayed at 852 MB -- 207,937 of 208,206 pages sat on SQLite's freelist
// inside a file that never shrank. The delete was never the problem; the
// missing VACUUM was.
//
// This drives the real resqlite native driver rather than package:sqlite3,
// because the open question was never whether VACUUM works in SQLite -- it
// was whether it survives resqlite's reader/writer split. `VACUUM` is not in
// `_statementIsReadOnly`'s verb set so it routes to the writer, and a
// top-level `execute` runs outside a transaction (SQLite rejects VACUUM
// inside one). Both of those are readings of the source; this test is what
// makes them observations.
//
// The statement pair below mirrors `ZonaiDb._vacuum`. Keep them in step: the
// trailing checkpoint is load-bearing, not decoration (see the WAL case
// asserted at the end).
void main() {
  setUpAll(() {
    final lib = File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  test(
    'VACUUM returns freed pages to the OS through the real resqlite driver',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      final tempDir = await Directory.systemTemp.createTemp('vacuum_reclaim_');
      final path = '${tempDir.path}/test.sqlite';
      final delegate = await ResqliteDelegate.open(path);
      final db = Raindrop(delegate);
      final dbFile = File(path);

      try {
        await db.execute(
          'CREATE TABLE "_log" ('
          '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          '"timestamp" INTEGER NOT NULL, '
          '"message" TEXT NOT NULL'
          ')',
        );

        // Enough rows to push the file well past any rounding: ~4k of text
        // per row over 2k rows is ~8 MB of payload, versus a page size of
        // 4096. The real report was 852 MB; the mechanism is scale-free.
        final padding = 'x' * 4000;
        for (var i = 0; i < 2000; i++) {
          await db.execute(
            'INSERT INTO "_log" ("timestamp", "message") VALUES (?, ?)',
            [i, padding],
          );
        }

        // In WAL mode the inserts land in the -wal sidecar first. Checkpoint
        // so "before" measures the main database file actually holding them,
        // which is what an operator sees with `ls -l`.
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        final sizeBefore = dbFile.lengthSync();
        expect(
          sizeBefore,
          greaterThan(4 * 1024 * 1024),
          reason: 'the fixture must be big enough for a shrink to be visible',
        );

        final deleted = await db.execute('DELETE FROM "_log"');
        expect(
          deleted.rowsAffected,
          2000,
          reason:
              'rowsAffected supplies the count without RETURNING *, which is '
              'what lets a multi-million-row _log be cleared at all',
        );
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');

        // The bug, reproduced: the rows are gone and the file is not smaller.
        expect(
          dbFile.lengthSync(),
          greaterThanOrEqualTo(sizeBefore),
          reason:
              'issue #28: DELETE moves pages to the freelist and the file on '
              'disk does not shrink -- if this ever fails, the premise of the '
              '--vacuum flag has changed',
        );

        // The fix.
        await db.execute('VACUUM');
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');

        final sizeAfter = dbFile.lengthSync();
        expect(
          sizeAfter,
          lessThan(sizeBefore ~/ 10),
          reason:
              'VACUUM rebuilds from live pages only, so an empty table should '
              'collapse to near-nothing (the report saw 852 MB -> 1.1 MB)',
        );

        // Survives the rewrite: VACUUM must not be a data-loss operation.
        await db.execute(
          'INSERT INTO "_log" ("timestamp", "message") VALUES (?, ?)',
          [1, 'after vacuum'],
        );
        final rows = await db.execute('SELECT "message" FROM "_log"');
        expect(rows.rows, hasLength(1));
      } finally {
        await delegate.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('data outside the cleared table survives a VACUUM', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('vacuum_survives_');
    final delegate = await ResqliteDelegate.open('${tempDir.path}/test.sqlite');
    final db = Raindrop(delegate);

    try {
      await db.execute(
        'CREATE TABLE "messages" ("id" INTEGER PRIMARY KEY, "body" TEXT)',
      );
      await db.execute('CREATE TABLE "_log" ("id" INTEGER PRIMARY KEY)');

      for (var i = 0; i < 294; i++) {
        await db.execute('INSERT INTO "messages" ("body") VALUES (?)', [
          'message $i',
        ]);
      }
      for (var i = 0; i < 500; i++) {
        await db.execute('INSERT INTO "_log" DEFAULT VALUES');
      }

      await db.execute('DELETE FROM "_log"');
      await db.execute('VACUUM');
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');

      final messages = await db.execute('SELECT COUNT(*) FROM "messages"');
      expect(
        messages.rows.single.single,
        294,
        reason:
            "the reporter's 294 messages and 34 channels came through their "
            'vacuum intact; application data must not be collateral',
      );
    } finally {
      await delegate.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
