part of zonai_db;

/// The nightly cron's floor: freelist space below which rewriting the log
/// database is not worth it.
///
/// A `VACUUM` is not free — it copies every live page, holds an exclusive
/// lock for the duration, and needs room for a second copy. Running it
/// nightly to reclaim a few megabytes would spend more than it recovers, so
/// this is a floor on "enough to bother", not a target.
///
/// **This is the cron's floor, not the verb's.** [ZonaiDb.reclaimSpace] takes
/// the floor as a parameter because the same number that is right for an
/// unattended nightly job is wrong for a human: an operator looking at
/// "9.5 MB reclaimable" on the Maintenance screen and pressing the button
/// gets a silent skip for the exact case they pressed for. The one caller
/// this belongs to is [ZonaiDb.reclaimLogSpace], which is what
/// [CleanupLogsCron] reaches over the wire.
const kCronReclaimFloorBytes = 16 * 1024 * 1024;

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

/// What one reclamation attempt did, and which database it did it to.
///
/// The general form of [LogSpaceReclamation]: same four fields plus [target],
/// so a result cannot be misread as being about a database it is not about.
/// [LogSpaceReclamation] stays as it is — it is the declared return type of
/// [ZonaiDb.reclaimLogSpace], which the cron's IPC path depends on.
typedef SpaceReclamation = ({
  String target,
  int reclaimableBytes,
  int reclaimedBytes,
  bool vacuumed,
  String? skipped,
});

extension _ReclaimSpaceX on ZonaiDb {
  /// Reads a no-argument pragma off [schema], throwing if it cannot be read.
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
  ///
  /// **Deliberately not [_StorageMetricsX._schemaPragmaInt], which is now the
  /// same statement generalised the same way.** That one swallows every
  /// failure into `null` because it backs a read-only storage report that has
  /// to render on a half-broken deployment. Here `null` would be read as a
  /// zero freelist, so an unreadable pragma would come back as "nothing to
  /// reclaim" — the one answer indistinguishable from success, on the path
  /// whose entire job is to tell those two apart. This one throws instead.
  Future<int> _reclaimPragmaInt(String schema, String pragma) async {
    final result = await _resqlite.transaction(
      (tx) => tx.execute('PRAGMA "$schema".$pragma', const []),
    );
    return result.rows.single.single! as int;
  }

  /// The file [schema] is attached to, whose length is what "reclaimed"
  /// means and whose volume has to have room for the rewrite.
  ///
  /// [kLogDbSchema] and [kRateLimitDbSchema] are the two `_openOnce` attaches
  /// (see `__utils.dart`); `main` is the application database itself, which is
  /// opened rather than attached and so has no constant of its own — spelled
  /// as a literal here for the same reason `_storageMetrics` spells it that
  /// way.
  ///
  /// An unknown schema throws rather than defaulting: this rewrites a file,
  /// and picking the wrong file silently is worse than refusing.
  File _schemaFile(String schema) => switch (schema) {
    'main' => _dbFile,
    kLogDbSchema => _logDbFile,
    kRateLimitDbSchema => _rateLimitDbFile,
    _ => throw ArgumentError.value(
      schema,
      'schema',
      'not a reclaimable database; expected one of '
          'main, $kLogDbSchema, $kRateLimitDbSchema',
    ),
  };

  /// Rewrites [schema]'s database file when enough of it is dead space, and
  /// says why not when it does not.
  ///
  /// The gate is two-sided on purpose. Rewriting is worth doing only when
  /// there is at least [minReclaimableBytes] on the freelist, and it is
  /// *possible* only when the volume has room for the copy `VACUUM` builds
  /// before swapping it in. A deployment that has already filled its disk
  /// fails the second test, and that is precisely the deployment where a
  /// silent skip is worst: the nightly job would run, report success, reclaim
  /// nothing, and leave an operator with no way to tell that from having
  /// nothing to reclaim. So that branch is the one that speaks up.
  ///
  /// [minReclaimableBytes] is the caller's to choose, and there is no default
  /// on purpose — see [kCronReclaimFloorBytes] for why the cron's number is
  /// the wrong one for a human pressing a button.
  Future<SpaceReclamation> _reclaimSpace({
    required String schema,
    required int minReclaimableBytes,
  }) async {
    await open();

    final file = _schemaFile(schema);

    final pageSize = await _reclaimPragmaInt(schema, 'page_size');
    final freelist = await _reclaimPragmaInt(schema, 'freelist_count');
    final pageCount = await _reclaimPragmaInt(schema, 'page_count');

    final reclaimable = freelist * pageSize;
    if (reclaimable < minReclaimableBytes) {
      return (
        target: schema,
        reclaimableBytes: reclaimable,
        reclaimedBytes: 0,
        vacuumed: false,
        skipped: null,
      );
    }

    // What the rewrite needs is room for the *live* pages, not for another
    // copy of the whole file — the dead ones are what it is dropping.
    final needed = (pageCount - freelist) * pageSize;
    final available = await freeDiskBytes(file.parent.path);

    // `null` is unknown, not zero (see [freeDiskBytes]). On a platform whose
    // free space cannot be read, going ahead is right: the rewrite either
    // works or fails with DiskFullException, which names the same remedy this
    // warning does. Refusing on unknown would mean never reclaiming anything
    // there.
    if (available != null && available < needed) {
      logger.warn(
        // Names the target: this verb no longer only ever means the log
        // database, so a warning that did not say which file it is about
        // would send an operator to grow the wrong volume.
        'The "$schema" database reclaimed no disk space. '
        '${formatBytes(reclaimable)} are on ${file.path}\'s freelist — '
        'free inside the database file, but not returned to the operating '
        'system. Rewriting the file is what returns them, and it needs '
        '${formatBytes(needed)} free to build its copy; '
        '${formatBytes(available)} are available. Extend the volume.',
        prefix: _prefix,
      );
      return (
        target: schema,
        reclaimableBytes: reclaimable,
        reclaimedBytes: 0,
        vacuumed: false,
        skipped: 'not enough free disk for the rewrite',
      );
    }

    final before = file.existsSync() ? file.lengthSync() : 0;
    await _vacuum(schema: schema);
    final after = file.existsSync() ? file.lengthSync() : 0;

    return (
      target: schema,
      reclaimableBytes: reclaimable,
      reclaimedBytes: before - after,
      vacuumed: true,
      skipped: null,
    );
  }
}
