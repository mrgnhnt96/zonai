// Ported from raindrop_sqlite's resqlite_delegate.dart -- excluded from
// zonai_schema's vendored raindrop copy (see
// libs/zonai_schema/tool/generate_raindrop_vendor.dart) because it needs
// `package:resqlite`, a git dependency that would block zonai_schema from
// publishing. apps/zonai is a distributed CLI binary, never published, so
// it's free to carry it directly.
//
// ⚠ THIS COPY HAS DELIBERATELY DIVERGED AHEAD OF UPSTREAM. Do not re-sync by
// overwriting it. As of 2026-08-13 the two differ by ~156 lines, and
// everything below that upstream does not have is load-bearing for zonai:
//
//   * `open`'s `attach` parameter, applied to BOTH connections. Upstream has
//     no concept of it. This is what puts `_log` and `_rate_limit` in files
//     of their own; without it they silently return to `zonai.sqlite`.
//   * `PRAGMA <schema>.journal_mode = WAL` on each attached database, which
//     does not inherit `main`'s and otherwise sits in `delete` mode, making
//     every `wal_checkpoint` against it a silent no-op.
//   * `open`'s `maxBytes`, backing `logDatabaseMaxSize`.
//
// The tests that would catch losing any of this live in `apps/zonai`
// (`log_database_split_test.dart`, `log_database_cap_test.dart`), so
// raindrop's own suite stays green while the damage is done. If upstream
// changes, MERGE its changes into this file -- do not copy it over.

import 'dart:async';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'hybrid_stream_engine.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_delegate.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_dialect.dart';
import 'package:resqlite/resqlite.dart' as rs;
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:sqlite3/sqlite3.dart';

/// Routes statements to resqlite’s reader [rs.Database.select] vs writer
/// [rs.Database.execute].
///
/// We cannot prepare statements on a scratch empty SQLite database to call
/// `Statement.isReadOnly`: preparing `SELECT … FROM t` fails there if `t`
/// does not exist, even though the same SQL is read-only on the real file.
bool _statementIsReadOnly(String query) {
  final verb = _mainSqlVerb(query);
  return verb == 'SELECT' || verb == 'VALUES' || verb == 'EXPLAIN';
}

bool _isWhitespace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C;

bool _isIdentifierChar(String s, int i) {
  if (i >= s.length) return false;
  final c = s.codeUnitAt(i);
  if (c >= 0x30 && c <= 0x39) return true;
  if (c >= 0x41 && c <= 0x5A) return true;
  if (c >= 0x61 && c <= 0x7A) return true;
  if (c == 0x5F) return true;
  return false;
}

int _skipWhitespaceComments(String s, int i) {
  while (i < s.length) {
    if (_isWhitespace(s.codeUnitAt(i))) {
      i++;
      continue;
    }
    // `--` line comment
    if (s.codeUnitAt(i) == 0x2D &&
        i + 1 < s.length &&
        s.codeUnitAt(i + 1) == 0x2D) {
      i += 2;
      while (i < s.length && s.codeUnitAt(i) != 0x0A) i++;
      continue;
    }
    // `/* */` block comment
    if (s.codeUnitAt(i) == 0x2F &&
        i + 1 < s.length &&
        s.codeUnitAt(i + 1) == 0x2A) {
      i += 2;
      while (i + 1 < s.length &&
          !(s.codeUnitAt(i) == 0x2A && s.codeUnitAt(i + 1) == 0x2F)) {
        i++;
      }
      i += 2;
      continue;
    }
    break;
  }
  return i;
}

/// Skips an SQL string starting at [i] (`'` or `"`) and returns the index
/// after the closing quote.
int _skipString(String s, int i) {
  final quote = s.codeUnitAt(i);
  i++;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == quote) {
      if (quote == 0x27 && i + 1 < s.length && s.codeUnitAt(i + 1) == 0x27) {
        i += 2;
        continue;
      }
      return i + 1;
    }
    i++;
  }
  return i;
}

int _skipWhitespaceCommentsStrings(String s, int i) {
  while (i < s.length) {
    final next = _skipWhitespaceComments(s, i);
    if (next != i) {
      i = next;
      continue;
    }
    final c = s.codeUnitAt(i);
    if (c == 0x27 || c == 0x22) {
      i = _skipString(s, i);
      continue;
    }
    break;
  }
  return i;
}

/// Uppercase SQL identifier / keyword starting at [i], and the index after it.
({String upper, int after})? _readUpperWord(String s, int i) {
  if (i >= s.length || !_isIdentifierChar(s, i)) return null;
  final start = i;
  i++;
  while (i < s.length && _isIdentifierChar(s, i)) i++;
  return (upper: s.substring(start, i).toUpperCase(), after: i);
}

/// After `WITH`, skips `RECURSIVE` if present and the comma-separated
/// `name AS ( … )` CTE list so the index sits at the enclosed statement.
int _skipWithClause(String s, int i) {
  i = _skipWhitespaceCommentsStrings(s, i);
  final iFirst = i;
  final first = _readUpperWord(s, i);
  if (first == null) {
    return i;
  }
  if (first.upper == 'RECURSIVE') {
    i = _skipWhitespaceCommentsStrings(s, first.after);
  } else {
    i = iFirst;
  }
  while (true) {
    i = _skipWhitespaceCommentsStrings(s, i);
    final name = _readUpperWord(s, i);
    if (name == null) return i;
    i = _skipWhitespaceCommentsStrings(s, name.after);
    final asTok = _readUpperWord(s, i);
    if (asTok == null || asTok.upper != 'AS') return i;
    i = _skipWhitespaceCommentsStrings(s, asTok.after);
    if (i >= s.length || s.codeUnitAt(i) != 0x28) return i;
    final startParen = i;
    var depth = 0;
    var j = startParen;
    while (j < s.length) {
      final c = s.codeUnitAt(j);
      if (c == 0x27 || c == 0x22) {
        j = _skipString(s, j);
        continue;
      }
      if (c == 0x28) {
        depth++;
        j++;
        continue;
      }
      if (c == 0x29) {
        depth--;
        j++;
        if (depth == 0) break;
        continue;
      }
      // skip `--` / `/*` inside parens via minimal handling: treat comment
      // starts outside strings only
      if (c == 0x2D &&
          j + 1 < s.length &&
          s.codeUnitAt(j + 1) == 0x2D &&
          depth > 0) {
        j += 2;
        while (j < s.length && s.codeUnitAt(j) != 0x0A) j++;
        continue;
      }
      if (c == 0x2F &&
          j + 1 < s.length &&
          s.codeUnitAt(j + 1) == 0x2A &&
          depth > 0) {
        j += 2;
        while (j + 1 < s.length &&
            !(s.codeUnitAt(j) == 0x2A && s.codeUnitAt(j + 1) == 0x2F)) {
          j++;
        }
        j += 2;
        continue;
      }
      j++;
    }
    i = j;
    i = _skipWhitespaceCommentsStrings(s, i);
    if (i < s.length && s.codeUnitAt(i) == 0x2C) {
      i++;
      continue;
    }
    break;
  }
  return i;
}

/// Uppercase main verb of the outer SQL statement (`SELECT`, `INSERT`, …),
/// after expanding a leading `WITH` clause if present.
String? _mainSqlVerb(String query) {
  var i = _skipWhitespaceCommentsStrings(query, 0);
  if (i >= query.length) return null;
  final w = _readUpperWord(query, i);
  if (w == null) return null;
  if (w.upper != 'WITH') {
    return w.upper;
  }
  i = _skipWithClause(query, w.after);
  i = _skipWhitespaceCommentsStrings(query, i);
  if (i >= query.length) return null;
  return _readUpperWord(query, i)?.upper;
}

/// Whether [query] contains a top-level `RETURNING` clause (not inside a
/// string literal), for `INSERT`/`UPDATE`/`DELETE` statements that yield rows.
///
/// resqlite’s [rs.Database.execute] discards row data; those statements must
/// use the writer [rs.Transaction.select] path instead of [SQLiteDelegate].
bool _statementHasReturning(String query) {
  var i = 0;
  while (i < query.length) {
    i = _skipWhitespaceCommentsStrings(query, i);
    if (i >= query.length) return false;
    final c = query.codeUnitAt(i);
    if (c == 0x27 || c == 0x22) {
      i = _skipString(query, i);
      continue;
    }
    final word = _readUpperWord(query, i);
    if (word != null) {
      if (word.upper == 'RETURNING') return true;
      i = word.after;
      continue;
    }
    i++;
  }
  return false;
}

DatabaseResult _fromWriteResult(rs.WriteResult wr) {
  return DatabaseResult(
    columns: const [],
    rows: const [],
    rowsAffected: wr.affectedRows,
    lastInsertedRowId: wr.lastInsertId != 0 ? wr.lastInsertId : null,
  );
}

/// [RaindropDelegate] backed by [rs.Database].
///
/// Mutations use resqlite’s writer isolate. Read-only statements and reactive
/// streams use a main-isolate [SQLiteDelegate] companion: resqlite reader
/// worker isolates segfault on table scans under Dart 3.12 dynamic FFI until
/// that native path is fixed upstream.
final class ResqliteDelegate extends RaindropDelegate {
  ResqliteDelegate._(this._database, this._reads, this._rawReads, this._streams)
    : super(dialect: const SQLiteDialect());

  final rs.Database _database;
  final SQLiteDelegate _reads;

  /// The connection behind [_reads], kept so it can be closed.
  ///
  /// SQLiteDelegate holds it privately and exposes no way to close it.
  final Database _rawReads;
  final HybridStreamEngine _streams;
  var _closed = false;

  /// Opens a SQLite database file with resqlite (writer + sqlite3 reads).
  ///
  /// [attach] maps a schema name to the database file joined onto the
  /// connection under it. An unqualified table name resolves into an attached
  /// database when `main` has no table by that name, which is what lets a
  /// table live in its own file without every caller learning where it went.
  /// [maxBytes] caps an attached database's file size, keyed by schema name.
  /// A schema with no entry is uncapped, which is the default everywhere.
  static Future<ResqliteDelegate> open(
    String path, {
    Map<String, String> attach = const {},
    Map<String, int> maxBytes = const {},
  }) async {
    // `rawReads` below opens the *same file* through package:sqlite3, which
    // by default dlopens its own, separate copy of libsqlite3 (the system
    // one on Linux/macOS) rather than reusing resqlite's already-loaded,
    // custom-built sqlite3mc library. Two independently-built SQLite
    // libraries touching the same connection/file in one process is a
    // classic footgun: package:sqlite3's calls land in a *different*
    // implementation than the one that created resqlite's handles (built
    // with different SQLITE_* flags, e.g. THREADSAFE=2 and several
    // OMIT/ENABLE flags resqlite's build sets), which don't share struct
    // layouts. Confirmed as a real, 100%-reproducible crash (not a race):
    // a minimal repro opening the same file via both libraries segfaulted
    // inside the *system* libsqlite3.so on the very first query, matching
    // the `sqlite3LeaveMutexAndCloseZombie` corruption seen in a real
    // deployed app. Forcing package:sqlite3 to reuse resqlite's own
    // `DynamicLibrary` (which exports the full standard sqlite3 C API --
    // see resqlite's `tool/build_native.dart`'s `_exportedSymbols`) means
    // both connections run the exact same code, eliminating the ABI
    // mismatch. Must happen before either connection is opened.
    //
    // This is why apps/zonai is pinned to sqlite3 2.x. 3.x removed
    // DynamicLibrary loading (and with it `open.overrideForAll`), and its
    // documented replacement --
    //
    //   user_defines:
    //     sqlite3:
    //       source: process
    //
    // -- is NOT the same guarantee, despite reading like it is. It resolves
    // to LookupInProcess(), i.e. dlsym(RTLD_DEFAULT), which binds to
    // whichever sqlite3 symbols are in the process *first*, in load order.
    // Measured here on macOS: DYLD_PRINT_LIBRARIES shows
    // /usr/lib/libsqlite3.dylib loaded as dyld image #103, pulled in
    // transitively by the system frameworks the Dart runtime links, before
    // main() runs. resqlite's dlopen happens later and can never outrank it,
    // so package:sqlite3 binds to Apple's SQLite (3.51.0, sourceid suffix
    // `aapl`) while resqlite keeps its own sqlite3mc (3.51.3) -- precisely
    // the two-library configuration described above. resqlite's RTLD_GLOBAL
    // dlopen does not help: a compiled probe that loaded nothing at all
    // still ran package:sqlite3 fine, so the install contributes nothing to
    // the binding.
    //
    // It also does not fail loudly -- resqlite exports the full standard
    // sqlite3 C API, so every symbol resolves and only the segfault tells
    // you. `process` guarantees *a* SQLite, not *ours*. Only an explicit
    // DynamicLibrary handle gives "one SQLite in this process": the
    // overrideForAll below, or (if 3.x ever becomes forced) bindings
    // rewritten to DynamicLibrary.lookupFunction -- see
    // docs/sqlite3-3x-migration.md.
    sqlite3_open.open.overrideForAll(() => rs.installedNativeLibrary);

    // SQLite disables foreign key enforcement by default on every new
    // connection — it is not a database-level setting, so declaring `ON
    // DELETE CASCADE` in a schema (see sqlite_ddl.dart's DDL generation)
    // has no effect at all until this pragma is set, and it must be set on
    // *both* connections opened below: `transaction()` (used for every
    // rule-checked mutation, per its own doc comment) runs against
    // `rawReads`, not `db` — a first pass that only set this on `db`
    // looked like it worked in isolation (a direct `db.execute('DELETE
    // ...')` really does cascade) but did nothing for a real request,
    // since real mutations never touch that connection at all. Confirmed
    // by tracing exactly which connection `transaction()` uses, not
    // guessed — a delete-with-cascade-configured-children integration test
    // left every child row behind until both connections got this pragma.
    final db = await rs.Database.open(path);
    await db.execute('PRAGMA foreign_keys = ON;');
    final rawReads = sqlite3.open(path);
    rawReads.execute('PRAGMA foreign_keys = ON;');

    // Same trap as the pragma above, and the reason [attach] is a parameter
    // of `open` rather than a statement a caller could run afterwards: an
    // `ATTACH` is a write, so executing one through [execute] would land on
    // `db` alone and every `SELECT` would be answered by a connection that
    // has never heard of the schema. Rows would be written and then be
    // unreadable -- worse than an outright failure, because nothing reports
    // it. Pinned by `attached_log_db_contract_test.dart`, which asserts that
    // asymmetry against the driver.
    //
    // The schema name is interpolated because SQLite does not accept a bound
    // parameter there; it is framework-controlled, never author input. The
    // file path is bound.
    for (final MapEntry(key: schema, value: file) in attach.entries) {
      await db.execute('ATTACH DATABASE ? AS "$schema"', [file]);
      rawReads.execute('ATTACH DATABASE ? AS "$schema"', [file]);
    }

    // An attached database keeps its *own* journal mode and defaults to
    // `delete`, regardless of what `main` is in -- resqlite puts `main` in
    // WAL, and measuring the pair showed `logdb` sitting in `delete` beside
    // it. Everything downstream quietly assumed otherwise: `_purge`'s
    // per-round `wal_checkpoint` and `_vacuum`'s trailing one are both no-ops
    // against a database with no WAL, as is the size limit below. Nothing
    // errors -- a checkpoint on a non-WAL database simply does nothing --
    // which is why this had to be measured rather than reasoned about.
    //
    // WAL also stops a log write from taking a lock readers wait on, which is
    // most of the point of moving the table out of the shared file.
    //
    // `PRAGMA journal_size_limit` was tried alongside this and deliberately
    // left out. Measured on the real driver: after 300 padded inserts, a
    // checkpoint at PASSIVE, FULL *and* RESTART reported full success
    // (`[0, 399, 399]` -- not busy, every frame copied) and left the `-wal`
    // at its full 1.6 MB with the limit set to 32 KB. Only TRUNCATE shrank
    // it, and TRUNCATE does that regardless of any limit. So the pragma buys
    // nothing on any path zonai takes: `_purge` checkpoints PASSIVE per round
    // (which returns pages for reuse, exactly as its comment claims, and does
    // not need the file to shrink) and `_vacuum` already uses TRUNCATE.
    for (final schema in attach.keys) {
      await db.execute('PRAGMA "$schema".journal_mode = WAL');
      rawReads.execute('PRAGMA "$schema".journal_mode = WAL');
    }

    // `max_page_count` is measured to be **per-connection and not persisted**:
    // setting it on the writer left a fresh handle -- and a later reopen --
    // reading the default 4294967294. Two consequences, both load-bearing.
    //
    // It has to be set on *both* connections or it caps nothing in practice,
    // because which one a write lands on depends on the statement: an
    // `INSERT ... RETURNING` (what raindrop's builder emits) is answered by
    // `rawReads`, a plain `INSERT` by the writer. Capping one would leave the
    // other as an open door.
    //
    // And because it does not persist, removing the setting from `zonai.yaml`
    // lifts the cap on the next start with nothing to reset -- which is the
    // behaviour an operator staring at a stalled log table would expect, and
    // the reason this needs no "uncap" path.
    for (final MapEntry(key: schema, value: bytes) in maxBytes.entries) {
      // Pages, not bytes, so the page size has to come from the file itself
      // rather than be assumed to be the 4096 default.
      final pageSize =
          rawReads.select('PRAGMA "$schema".page_size').single.values.first!
              as int;
      final pages = bytes ~/ pageSize;
      // SQLite refuses to set a maximum below the current size, so a cap
      // under one page would be silently meaningless rather than strict.
      if (pages < 1) continue;
      await db.execute('PRAGMA "$schema".max_page_count = $pages');
      rawReads.execute('PRAGMA "$schema".max_page_count = $pages');
    }

    final reads = SQLiteDelegate(rawReads);
    final streams = HybridStreamEngine(reads.execute);
    await db.bindWriteInvalidation(streams.onDependencyChanges);
    return ResqliteDelegate._(db, reads, rawReads, streams);
  }

  Future<void> close() async {
    _closed = true;
    _streams.close();
    await _database.close();
    // sqlite3 2.x API; 3.x renamed this to close(). See the pin in pubspec.
    _rawReads.dispose();
  }

  Future<DatabaseResult> _executeRead(String query, List<Object?> values) =>
      _reads.execute(query, values);

  @override
  Future<DatabaseResult> execute(String query, List<Object?> values) async {
    if (_statementIsReadOnly(query)) {
      return _executeRead(query, values);
    }
    if (_statementHasReturning(query)) {
      return _executeRead(query, values);
    }
    final wr = await _database.execute(query, values);
    return _fromWriteResult(wr);
  }

  @override
  Stream<DatabaseResult> streamQuery(String query, List<Object?> values) {
    if (_closed) {
      throw StateError('Database is closed.');
    }
    if (!_statementIsReadOnly(query)) {
      throw ArgumentError.value(
        query,
        'query',
        'streamQuery only supports read-only SQL (SELECT, VALUES, EXPLAIN).',
      );
    }
    return _streams.stream(query, values);
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(TransactionDelegate delegate) transaction,
  ) async {
    // Raindrop transactions run on the companion sqlite3 connection so
    // INSERT … RETURNING can write without fighting resqlite's writer
    // BEGIN IMMEDIATE lock. Stream subscribers must be refreshed after
    // commit -- `_reads.transaction` (SQLiteDelegate) only issues COMMIT
    // after the callback below returns, so the notification has to fire
    // after `_reads.transaction` itself resolves, not from inside the
    // callback, or subscribers requery against the pre-commit state.
    final result = await _reads.transaction((tx) async {
      final delegate = _ResqliteTransactionDelegate(dialect, tx);
      return transaction(delegate);
    });
    _streams.onDependencyChanges(rs.TableDependencies.unknown);
    return result;
  }
}

final class _ResqliteTransactionDelegate extends TransactionDelegate {
  _ResqliteTransactionDelegate(super.dialect, this._inner);

  final TransactionDelegate _inner;

  @override
  Future<DatabaseResult> execute(String query, List<Object?> values) =>
      _inner.execute(query, values);

  @override
  Future<T> transaction<T>(
    Future<T> Function(TransactionDelegate delegate) transaction,
  ) => _inner.transaction(transaction);

  @override
  Never rollback() => throw const TransactionRollback();
}
