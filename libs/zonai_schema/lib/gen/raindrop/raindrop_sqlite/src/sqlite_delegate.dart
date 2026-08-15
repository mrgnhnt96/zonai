// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart';
import 'package:sqlite3/common.dart';

/// {@template sqlite_delegate}
/// Delegate for the SQLite database.
/// {@endtemplate}
class SQLiteDelegate extends RaindropDelegate with _DatabaseDelegate {
  /// {@macro sqlite_delegate}

  SQLiteDelegate(CommonDatabase database)
      : _database = database,
        super(
          dialect: SQLiteDialect(
            supportsUpdateDeleteLimit: probeForLimitSupport(database),
          ),
        );

  /// Whether [database] was compiled with `SQLITE_ENABLE_UPDATE_DELETE_LIMIT`,
  /// which decides how a capped write renders, see `LimitedWriteClause`.
  static bool probeForLimitSupport(CommonDatabase database) =>
      _hasCompileOption(database, 'SQLITE_ENABLE_UPDATE_DELETE_LIMIT');

  /// Whether [database] was compiled with [name]. Any failure answers false,
  /// including the build that omitted the diagnostic function itself.
  static bool _hasCompileOption(CommonDatabase database, String name) {
    try {
      final result = database.select(
        'SELECT sqlite_compileoption_used(?) AS used',
        [name],
      );
      return result.first['used'] == 1;
    } on Object {
      return false;
    }
  }

  @override
  final CommonDatabase _database;

  /// Closes the underlying connection.
  ///
  /// The database is held privately, so without this a caller holding only
  /// the delegate has no way to release the connection.
  ///
  /// Named `close()` but calls `dispose()`: this package is pinned to
  /// sqlite3 2.x (see pubspec), which is where ResqliteDelegate's
  /// `open.overrideForAll` lives, and 2.x spells this `dispose()`. The
  /// method keeps the `close()` name because that is the API consumers
  /// already hold.
  void close() => _database.dispose();

  /// Serializes every top-level [execute]/[transaction] call against this
  /// connection.
  ///
  /// `sqlite3` only allows one transaction open at a time per connection — a
  /// second `BEGIN` before the first `COMMIT`/`ROLLBACK` throws "cannot start
  /// a transaction within a transaction" rather than queuing. Without this
  /// chain, two concurrent callers sharing one [SQLiteDelegate] (e.g.
  /// concurrent HTTP requests reusing the read connection) race on that
  /// `BEGIN` and one of them fails. Chaining onto a single `Future` forces
  /// each call to wait for the previous one's `COMMIT`/`ROLLBACK`.
  Future<void> _chain = Future.value();

  Future<T> _serialized<T>(Future<T> Function() body) {
    final ticket = _chain.then((_) => body());
    _chain = ticket.then((_) {}, onError: (_) {});
    return ticket;
  }

  @override
  Future<DatabaseResult> execute(String query, List<Object?> values) {
    return _serialized(() => super.execute(query, values));
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(TransactionDelegate delegate) transaction,
  ) {
    return _serialized(() => _runTransaction(transaction));
  }

  Future<T> _runTransaction<T>(
    Future<T> Function(TransactionDelegate delegate) transaction,
  ) async {
    final tx = _TransactionDelegate(_database, this.dialect);
    _database.execute('BEGIN', []);

    try {
      final result = await transaction(tx);
      _database.execute('COMMIT', []);
      return result;
    } catch (_) {
      _database.execute('ROLLBACK', []);
      rethrow;
    }
  }
}

class _TransactionDelegate extends TransactionDelegate with _DatabaseDelegate {
  _TransactionDelegate(this._database, super.dialect, [super.depth]);

  @override
  final CommonDatabase _database;

  @override
  Future<T> transaction<T>(
    Future<T> Function(TransactionDelegate delegate) transaction,
  ) async {
    final savePoint = 'sp_$depth';
    final tx = _TransactionDelegate(_database, this.dialect, depth + 1);
    _database.execute('SAVEPOINT $savePoint', []);

    try {
      final result = await transaction(tx);
      _database.execute('RELEASE SAVEPOINT $savePoint', []);
      return result;
    } catch (_) {
      _database.execute('ROLLBACK TO $savePoint', []);
      rethrow;
    }
  }

  @override
  Never rollback() => throw const TransactionRollback();
}

mixin _DatabaseDelegate on Delegate {
  CommonDatabase get _database;

  @override
  Future<DatabaseResult> execute(String query, List<Object?> values) {
    final stmt = _database.prepare(query);
    try {
      final modifiesDatabase = !stmt.isReadOnly;
      final resultSet = stmt.select(values);
      final lastRowId = _database.lastInsertRowId;

      return Future.value(
        DatabaseResult(
          columns: resultSet.columnNames,
          rows: [...resultSet.map((row) => row.values)],
          rowsAffected: modifiesDatabase ? _database.updatedRows : 0,
          lastInsertedRowId:
              modifiesDatabase && lastRowId != 0 ? lastRowId : null,
        ),
      );
    } finally {
      // sqlite3 2.x API; 3.x renamed this to close(). See the pin in pubspec.
      stmt.dispose();
    }
  }
}
