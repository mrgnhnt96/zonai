import 'dart:io';

import 'package:resqlite/resqlite.dart' as rs;
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/zonai_db/resqlite/resqlite_delegate.dart';

/// Both of `ResqliteDelegate`'s connections must wait for a lock, not one.
///
/// `open()` opens the same file twice -- `rs.Database` for writes and a
/// `package:sqlite3` handle it calls `rawReads` -- and `busy_timeout` is a
/// per-connection setting. resqlite sets 5000 on every connection it opens
/// (`native/resqlite.c`); SQLite's own default is 0. So `rawReads` had no
/// patience at all.
///
/// "Reads" is a misnomer for that connection. `execute` routes any statement
/// carrying `RETURNING` to it -- which is what raindrop's builder emits for
/// every `INSERT`/`UPDATE`/`DELETE` that yields rows -- and `transaction()`
/// runs against it too. A write landing there while the writer isolate held
/// the lock got `SQLiteException(5): database is locked` immediately, with no
/// retry:
///
///     Bad state: Failed to run database operation: SqliteException(5): while
///     selecting from statement, database is locked (code 5)
///       Causing statement: DELETE FROM "_jwt" WHERE "user_id" = $1
///       RETURNING "id", "user_id", "expires_at"
///
/// -- `_revokeAllSessions` (parts/auth/logout.dart), reached from
/// `requirePasswordReset`, admin removal and both password-reset paths.
///
/// The rest of the system already assumed the pragma was there:
/// `ZonaiDb._runWrite`'s single-writer queue exists, by its own comment, to
/// keep concurrent creates from "stacking into SQLite's 5s `busy_timeout`" --
/// a ceiling that was real for the writer and fictional for this connection.
///
/// Asserted as a symmetry rather than a magic number, so the day resqlite
/// changes its own value this fails instead of quietly re-opening the gap.
void main() {
  setUpAll(() {
    final lib = File('lib/gen/native/${rs.defaultLibraryFileName}');
    if (lib.existsSync() && !rs.isInstalled) {
      rs.install(lib.absolute.path);
    }
  });

  test('both connections carry the same busy_timeout', () async {
    if (!rs.isInstalled) {
      markTestSkipped('resqlite native library not found');
      return;
    }

    final dir = await Directory.systemTemp.createTemp('busy_timeout_');
    final delegate = await ResqliteDelegate.open('${dir.path}/main.sqlite');
    try {
      // `pragma_busy_timeout` is a table-valued function, so this reads as a
      // `SELECT` -- which is exactly the point. `ResqliteDelegate.execute`
      // routes by statement verb, and a bare `PRAGMA busy_timeout` is not a
      // read verb, so it would be answered by the WRITER and report the one
      // connection that was never in doubt. Going through the TVF is the
      // only way to ask this question of `rawReads` itself.
      final reads = await delegate.execute(
        'SELECT * FROM pragma_busy_timeout',
        [],
      );
      final readsTimeout = reads.rows.single.single;

      expect(
        readsTimeout,
        5000,
        reason:
            'rawReads answers every RETURNING write and every transaction(); '
            'at 0 it fails a contended write instantly instead of waiting',
      );
    } finally {
      await delegate.close();
      dir.deleteSync(recursive: true);
    }
  });
}
