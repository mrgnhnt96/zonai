part of zonai_db;

/// Tables a [PurgeRecordsRequest] is allowed to touch.
///
/// Derived from the framework's own table list rather than written out, so a
/// new internal table is covered without anyone remembering to add it here —
/// and, more importantly, so an *application* table can never appear in it.
///
/// `_photos` is the one exclusion. Deleting a photo row also deletes the file
/// behind it (`_deletePhotoFile`, reached from the per-row delete path), and a
/// bulk `DELETE` has no per-row step to hang that on. Purging it would orphan
/// every file it removed rows for. `_cleanup_unreferenced_photos` already does
/// that job properly, one row at a time.
final Set<String> _purgeableTables = InternalDbArtifacts.tableNames.difference({
  '_photos',
});

/// Rows removed per statement.
///
/// A purge holds no rows in memory, so this is not a memory bound the way
/// `_maxRowsPerDelete` is. It bounds the **WAL**: every page a `DELETE`
/// touches is written there before the transaction commits, so deleting a
/// multi-million-row backlog in one statement needs free disk proportional to
/// the backlog — precisely when a runaway table has left none.
///
/// Chunking trades atomicity for the ability to make progress at all. An
/// interrupted purge leaves the table partly drained, which is exactly right
/// for retention: there is no invariant spanning rows older than a cutoff,
/// and the next run continues from wherever this one stopped.
const _purgeChunkSize = 10000;

/// Ceiling on rounds within a single purge, so a table being written faster
/// than it drains cannot spin forever. Hitting it is reported, not silent —
/// the run ends early and says how much is left to do.
const _maxPurgeRounds = 1000;

extension _PurgeX on ZonaiDb {
  /// Deletes every row matching [where] as a single statement, returning how
  /// many were removed.
  ///
  /// This is the bulk counterpart to [_delete], and it deliberately skips the
  /// machinery that one runs: no read-back of the matched rows, no per-row
  /// rules dispatch, no sanitization, no `before`/`after` extension callbacks.
  /// That machinery is correct for author tables and unusable for retention —
  /// `_delete` begins by SELECTing every row it is about to remove, with no
  /// limit, and materializing them all. A retention sweep over a few million
  /// rows cannot survive it, which is exactly the state the field reported.
  ///
  /// Skipping row rules is safe here only because of the two gates above it:
  ///
  ///  * [table] must be one of [_purgeableTables] — the framework's own
  ///    tables, whose rules are generated rather than author-supplied, so
  ///    there is no application policy to bypass.
  ///  * [jwt] must be an admin identity. Scheduled crons satisfy this through
  ///    [CronJwt] (`isAdmin: true`), so they need no special-casing; anything
  ///    reaching this without admin is refused the same way a table-rules
  ///    denial would refuse it.
  ///
  /// Both are enforced here, host-side, rather than trusted from the caller:
  /// the request arrives over IPC from a worker process.
  Future<int> _purge({
    required String table,
    required Where where,
    required Jwt? jwt,
  }) async {
    if (jwt?.admin.isAdmin != true) {
      throw const TableAccessDeniedException(table: '', operation: 'purge');
    }

    if (!_purgeableTables.contains(table)) {
      throw TableAccessDeniedException(table: table, operation: 'purge');
    }

    // Built once and re-executed: the statement is identical every round, so
    // regenerating it per chunk would be an IPC hop to the operations worker
    // for the same string. The operations layer rewrites a limited delete
    // into `pk IN (SELECT pk ... LIMIT n)`, since the bundled SQLite cannot
    // parse `DELETE ... LIMIT` -- so chunking costs nothing extra to express.
    final operation = await _getOperation(
      DeleteOperationRequest(
        table: table,
        where: where,
        limit: _purgeChunkSize,
        jwt: jwt,
      ),
    );

    final db = await open();
    var total = 0;

    for (var round = 0; round < _maxPurgeRounds; round++) {
      final (error, result) = await _execute((
        operation.query,
        operation.values,
      ));

      if (error != null || result == null) {
        _throwDatabaseError(
          error,
          table: table,
          failure: ([cause]) =>
              RecordDeleteFailedException(table: table, cause: cause),
        );
      }

      total += result.rowsAffected;

      // A short round means the predicate is drained; anything else would be
      // another statement returning zero.
      if (result.rowsAffected < _purgeChunkSize) {
        logger.verbose('Purged $total rows from $table', prefix: _prefix);
        return total;
      }

      // Hand the WAL back between rounds. PASSIVE rather than TRUNCATE: it
      // never blocks on a reader, and it is enough for the property that
      // matters here -- the WAL is reused from the start instead of growing
      // for the whole backlog. That is what lets a nearly-full volume drain
      // at all, which one large transaction cannot do.
      //
      // Schema-qualified, because a WAL belongs to a *file*: the disposable
      // tables live in attached databases of their own, and an unqualified
      // checkpoint would keep handing back `main`'s WAL while the one
      // actually growing -- the only one this loop exists to bound -- was
      // never touched.
      final schema = _disposableTableSchemas[table];
      await db.execute(
        schema == null
            ? 'PRAGMA wal_checkpoint(PASSIVE)'
            : 'PRAGMA "$schema".wal_checkpoint(PASSIVE)',
      );
    }

    // Reaching here means every round was full. Either the table is being
    // written faster than it drains, or the predicate does not narrow --
    // both are worth saying out loud rather than looping forever.
    logger.warn(
      'Purge of $table stopped after $_maxPurgeRounds rounds with $total rows '
      'removed; more rows still match. It will continue on the next run.',
    );

    return total;
  }
}
