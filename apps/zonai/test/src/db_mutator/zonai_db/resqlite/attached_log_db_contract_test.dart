import 'dart:io';

import 'package:resqlite/resqlite.dart' as rs;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/zonai_db/resqlite/resqlite_delegate.dart';
import 'package:zonai_schema/zonai_schema.dart';

// The properties a separate `_log` database would rest on, checked against the
// real driver before anything is built on top of them.
//
// The motivating case (2026-08-13): `_log` grew to 4.6M rows and filled a
// production volume, and every recovery path zonai ships needed a write the
// full disk was denying. Moving the table to its own file makes `unlink` a
// recovery option, scopes VACUUM's exclusive lock to disposable data, and
// makes a page cap usable -- `max_page_count` bounds a *file*, so on a shared
// database it would fail application writes rather than log writes.
//
// Each test below is a claim the design would otherwise be assuming. They are
// about SQLite and the resqlite driver, not about zonai's own code, which is
// exactly why they are worth pinning: if a driver upgrade changes one of
// these, the failure should name the assumption rather than surface as a
// mystery in the log pipeline.
void main() {
  setUpAll(() {
    final lib = File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  Future<(ResqliteDelegate, Raindrop, Directory)> openPair(String prefix) async {
    final dir = await Directory.systemTemp.createTemp(prefix);
    final delegate = await ResqliteDelegate.open('${dir.path}/main.sqlite');
    return (delegate, Raindrop(delegate), dir);
  }

  test(
    'a single ATTACH reaches only the write connection -- reads route to a '
    'second connection that has never heard of the database',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      final (delegate, db, dir) = await openPair('attach_resolve_');
      try {
        await db.execute('ATTACH DATABASE ? AS logdb', [
          '${dir.path}/log.sqlite',
        ]);
        await db.execute(
          'CREATE TABLE "logdb"."_log" ("id" INTEGER PRIMARY KEY, "m" TEXT)',
        );

        // The write half works: an unqualified name does resolve into the
        // attached database when main has no such table, which is the
        // property that would make the split transparent.
        await db.execute('INSERT INTO "_log" ("m") VALUES (?)', ['written']);

        // The read half does not. `ResqliteDelegate` opens the same file
        // twice -- `rs.Database` for writes and a `package:sqlite3` handle
        // for reads -- and routes by statement verb. An `ATTACH` is a write,
        // so it lands on one connection and the SELECT is answered by the
        // other, which has no `logdb` and therefore no `_log`.
        //
        // The delegate already carries this scar for `PRAGMA foreign_keys`,
        // whose comment records that setting it on one connection "looked
        // like it worked in isolation but did nothing for a real request".
        // Same trap, different statement: the attach has to be part of
        // opening *each* connection, not a statement executed once.
        await expectLater(
          db.execute('SELECT "m" FROM "_log"'),
          throwsA(
            predicate(
              (e) => '$e'.contains('no such table'),
              'fails with "no such table"',
            ),
          ),
          reason:
              'if this ever starts passing, the driver has stopped splitting '
              'reads and writes across connections -- which would change '
              'where the attach belongs',
        );

        // The row really did land in the other file, via the writer. Checked
        // through a handle of its own: every read through the delegate goes
        // to the connection that cannot see `logdb`, including this one, so
        // there is no way to confirm it from inside.
        final direct = sqlite3.open('${dir.path}/log.sqlite');
        try {
          expect(
            direct.select('SELECT COUNT(*) AS c FROM "_log"').single['c'],
            1,
            reason:
                'the write half of the split works -- which is what makes '
                'this asymmetry dangerous rather than merely broken: log '
                'rows would be written and then be unreadable',
          );
        } finally {
          direct.dispose();
        }
      } finally {
        await delegate.close();
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a page cap on the attached database stops log writes without touching '
    'application writes -- the property that makes a cap safe at all',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      final (delegate, db, dir) = await openPair('attach_cap_');
      try {
        await db.execute('ATTACH DATABASE ? AS logdb', [
          '${dir.path}/log.sqlite',
        ]);
        await db.execute(
          'CREATE TABLE "main"."app" ("id" INTEGER PRIMARY KEY, "m" TEXT)',
        );
        await db.execute(
          'CREATE TABLE "logdb"."_log" ("id" INTEGER PRIMARY KEY, "m" TEXT)',
        );

        // Deliberately tiny, so the ceiling is reachable in a test.
        await db.execute('PRAGMA logdb.max_page_count = 8');

        final padding = 'x' * 2000;
        Object? logFailure;
        try {
          for (var i = 0; i < 500; i++) {
            await db.execute('INSERT INTO "_log" ("m") VALUES (?)', [padding]);
          }
        } catch (e) {
          logFailure = e;
        }

        expect(
          logFailure,
          isNotNull,
          reason: 'the cap must actually stop log writes, or it caps nothing',
        );
        expect(
          '$logFailure'.toLowerCase(),
          contains('full'),
          reason:
              'it should surface as SQLITE_FULL against the log database, '
              'which is what DiskFullException keys on',
        );

        // The whole point: the application database is unaffected.
        await db.execute('INSERT INTO "main"."app" ("m") VALUES (?)', [
          padding,
        ]);
        final app = await db.execute('SELECT COUNT(*) FROM "main"."app"');
        expect(
          app.rows.single.single,
          1,
          reason:
              'a cap on the shared file would have failed this write too, '
              'which is why the cap cannot land before the split',
        );
      } finally {
        await delegate.close();
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'VACUUM can target the attached database alone, so reclaiming log space '
    'does not take an exclusive lock on application data',
    () async {
      if (!rs.isInstalled) {
        markTestSkipped('resqlite native library not found');
        return;
      }

      final (delegate, db, dir) = await openPair('attach_vacuum_');
      final logFile = File('${dir.path}/log.sqlite');
      try {
        await db.execute('ATTACH DATABASE ? AS logdb', [logFile.path]);
        await db.execute(
          'CREATE TABLE "logdb"."_log" ("id" INTEGER PRIMARY KEY, "m" TEXT)',
        );

        final padding = 'x' * 4000;
        for (var i = 0; i < 500; i++) {
          await db.execute('INSERT INTO "_log" ("m") VALUES (?)', [padding]);
        }
        await db.execute('PRAGMA logdb.wal_checkpoint(TRUNCATE)');
        final before = logFile.lengthSync();
        expect(before, greaterThan(1024 * 1024));

        await db.execute('DELETE FROM "_log"');
        await db.execute('VACUUM logdb');
        await db.execute('PRAGMA logdb.wal_checkpoint(TRUNCATE)');

        expect(
          logFile.lengthSync(),
          lessThan(before ~/ 2),
          reason: 'a schema-qualified VACUUM must actually rewrite that file',
        );
      } finally {
        await delegate.close();
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
