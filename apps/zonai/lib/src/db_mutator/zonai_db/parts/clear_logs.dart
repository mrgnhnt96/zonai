part of zonai_db;

extension _ClearLogsX on ZonaiDb {
  /// Deletes rows from `_log`, optionally only those older than [before].
  ///
  /// Runs as a plain statement rather than `delete(...).returning()`: the
  /// builder's `.returning()` appends `RETURNING *`, which pulls every deleted
  /// row back over FFI and decodes it into a `LogEntry` just to count them.
  /// Databases that accumulated millions of rows under an older CLI (issue
  /// #28: 3.8M) are exactly the ones running this, and are exactly the ones
  /// that cannot afford to materialize the result set. `rowsAffected` is the
  /// same number for free.
  Future<int> _clearLogs({DateTime? before}) async {
    final db = await open();
    final table = _logTableName;

    final result = switch (before) {
      null => await db.execute('DELETE FROM "$table"'),
      final cutoff => await db.execute(
        'DELETE FROM "$table" WHERE "${logs.timestamp.name}" < ?',
        [cutoff.millisecondsSinceEpoch],
      ),
    };

    return result.rowsAffected;
  }

  /// Rewrites a database file, returning space freed by deletes to the OS.
  ///
  /// A `DELETE` only moves pages onto SQLite's freelist; the file itself never
  /// shrinks. `VACUUM` rebuilds it from the live pages only. The trailing
  /// checkpoint matters just as much in WAL mode: without it the reclaimed
  /// pages sit in the `-wal` sidecar and the numbers an operator checks
  /// afterwards still do not move.
  ///
  /// [schema] picks the file. `null` means `main`; [kLogDbSchema] means the
  /// log database. This is what keeps the rewrite's exclusive lock off
  /// application data when the thing being reclaimed is logs -- verified
  /// against the real driver in `attached_log_db_contract_test.dart`, and the
  /// reason vacuuming from a cron is viable at all.
  ///
  /// Must not run inside a transaction -- SQLite rejects `VACUUM` there --
  /// which is why the caller reaches this through [ZonaiDb.vacuum] rather
  /// than folding it into another unit of work.
  Future<void> _vacuum({String? schema}) async {
    final db = await open();
    if (schema == null) {
      await db.execute('VACUUM');
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      return;
    }
    await db.execute('VACUUM "$schema"');
    await db.execute('PRAGMA "$schema".wal_checkpoint(TRUNCATE)');
  }
}
