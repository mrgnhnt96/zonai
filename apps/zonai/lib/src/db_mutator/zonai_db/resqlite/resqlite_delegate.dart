// Ported from raindrop_sqlite's resqlite_delegate.dart -- excluded from
// zonai_schema's vendored raindrop copy (see
// libs/zonai_schema/tool/generate_raindrop_vendor.dart) because it needs
// `package:resqlite`, a git dependency that would block zonai_schema from
// publishing. apps/zonai is a distributed CLI binary, never published, so
// it's free to carry it directly. Re-sync by hand if raindrop_sqlite's
// upstream version of this file changes.

import 'dart:async';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'hybrid_stream_engine.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_delegate.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_dialect.dart';
import 'package:resqlite/resqlite.dart' as rs;
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
  ResqliteDelegate._(
    this._database,
    this._reads,
    this._rawReads,
    this._streams,
  )
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
  static Future<ResqliteDelegate> open(String path) async {
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
    // Under sqlite3 2.x this was forced at runtime here with
    // `open.overrideForAll(() => rs.installedNativeLibrary)`. sqlite3 3.x
    // removed DynamicLibrary loading, so the same guarantee -- one SQLite
    // in this process, never a second dlopen'd copy -- now comes from the
    // build hook, declared by the app:
    //
    //   user_defines:
    //     sqlite3:
    //       source: process
    //
    // which resolves to LookupInProcess(). resqlite already dlopens its
    // library with RTLD_GLOBAL on Linux/Android (see native_library.dart)
    // so its symbols are visible for that lookup.

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
    final reads = SQLiteDelegate(rawReads);
    final streams = HybridStreamEngine(reads.execute);
    await db.bindWriteInvalidation(streams.onDependencyChanges);
    return ResqliteDelegate._(db, reads, rawReads, streams);
  }

  Future<void> close() async {
    _closed = true;
    _streams.close();
    await _database.close();
    _rawReads.close();
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
  ) =>
      _inner.transaction(transaction);

  @override
  Never rollback() => throw const TransactionRollback();
}
