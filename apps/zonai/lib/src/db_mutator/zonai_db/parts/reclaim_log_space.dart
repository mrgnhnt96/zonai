part of zonai_db;

/// Freelist space below which rewriting the log database is not worth it.
///
/// A `VACUUM` is not free — it copies every live page, holds an exclusive
/// lock for the duration, and needs room for a second copy. Running it
/// nightly to reclaim a few megabytes would spend more than it recovers, so
/// this is a floor on "enough to bother", not a target.
const _minReclaimableBytes = 16 * 1024 * 1024;

/// What one reclamation attempt did.
///
/// [skipped] is the reason nothing was rewritten, or `null` when something
/// was — including the legitimate case of there being nothing worth doing.
typedef LogSpaceReclamation = ({
  int reclaimableBytes,
  int reclaimedBytes,
  bool vacuumed,
  String? skipped,
});

extension _ReclaimLogSpaceX on ZonaiDb {
  /// Reads a no-argument pragma off the log database.
  ///
  /// Through `transaction` rather than `execute`, and not by accident:
  /// `PRAGMA` is not a read verb, so [ResqliteDelegate.execute] routes it to
  /// the writer, which discards row data and would hand back an empty result
  /// for every one of these. `transaction` runs on the companion sqlite3
  /// connection, which returns rows.
  ///
  /// The `pragma_*` table-valued functions are not an alternative here:
  /// `pragma_freelist_count` accepts no arguments at all, so there is no way
  /// to aim it at an attached database, and the `"logdb".pragma_page_count`
  /// spelling silently reads a different database (measured: 1 page against a
  /// real 202) rather than failing.
  Future<int> _logDbPragmaInt(String pragma) async {
    final result = await _resqlite.transaction(
      (tx) => tx.execute('PRAGMA "$kLogDbSchema".$pragma', const []),
    );
    return result.rows.single.single! as int;
  }

  /// Rewrites the log database when enough of it is dead space, and says why
  /// not when it does not.
  ///
  /// The gate is two-sided on purpose. Rewriting is worth doing only when
  /// there is enough on the freelist to matter, and it is *possible* only
  /// when the volume has room for the copy `VACUUM` builds before swapping it
  /// in. A deployment that has already filled its disk fails the second test,
  /// and that is precisely the deployment where a silent skip is worst: the
  /// nightly job would run, report success, reclaim nothing, and leave an
  /// operator with no way to tell that from having nothing to reclaim. So
  /// that branch is the one that speaks up.
  Future<LogSpaceReclamation> _reclaimLogSpace() async {
    await open();

    final pageSize = await _logDbPragmaInt('page_size');
    final freelist = await _logDbPragmaInt('freelist_count');
    final pageCount = await _logDbPragmaInt('page_count');

    final reclaimable = freelist * pageSize;
    if (reclaimable < _minReclaimableBytes) {
      return (
        reclaimableBytes: reclaimable,
        reclaimedBytes: 0,
        vacuumed: false,
        skipped: null,
      );
    }

    // What the rewrite needs is room for the *live* pages, not for another
    // copy of the whole file — the dead ones are what it is dropping.
    final needed = (pageCount - freelist) * pageSize;
    final available = await freeDiskBytes(_logDbFile.parent.path);

    // `null` is unknown, not zero (see [freeDiskBytes]). On a platform whose
    // free space cannot be read, going ahead is right: the rewrite either
    // works or fails with DiskFullException, which names the same remedy this
    // warning does. Refusing on unknown would mean never reclaiming anything
    // there.
    if (available != null && available < needed) {
      logger.warn(
        'Log retention reclaimed no disk space. '
        '${formatBytes(reclaimable)} are on ${_logDbFile.path}\'s freelist — '
        'free inside the database file, but not returned to the operating '
        'system. Rewriting the file is what returns them, and it needs '
        '${formatBytes(needed)} free to build its copy; '
        '${formatBytes(available)} are available. Extend the volume.',
        prefix: _prefix,
      );
      return (
        reclaimableBytes: reclaimable,
        reclaimedBytes: 0,
        vacuumed: false,
        skipped: 'not enough free disk for the rewrite',
      );
    }

    final before = _logDbFile.existsSync() ? _logDbFile.lengthSync() : 0;
    await _vacuum(schema: kLogDbSchema);
    final after = _logDbFile.existsSync() ? _logDbFile.lengthSync() : 0;

    return (
      reclaimableBytes: reclaimable,
      reclaimedBytes: before - after,
      vacuumed: true,
      skipped: null,
    );
  }
}
