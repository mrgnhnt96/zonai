part of zonai_db;

extension _StorageMetricsX on ZonaiDb {
  /// Reads a no-argument pragma off an attached schema, or `null` when it
  /// cannot be read.
  ///
  /// Through `transaction` rather than `execute`, and not by accident:
  /// `PRAGMA` is not a read verb, so [ResqliteDelegate.execute] routes it to
  /// the writer, which discards row data and would hand back an empty result
  /// for every one of these. `transaction` runs on the companion sqlite3
  /// connection, which returns rows. This is the same trick
  /// [_ReclaimLogSpaceX._logDbPragmaInt] documents, generalised over the
  /// schema — and it is generalised here rather than reused because that one
  /// hard-codes [kLogDbSchema] and this needs all three files.
  ///
  /// The `pragma_*` table-valued functions are not an alternative:
  /// `pragma_freelist_count` accepts no arguments at all, so there is no way
  /// to aim it at an attached database, and the `"logdb".pragma_page_count`
  /// spelling silently reads a *different* database rather than failing.
  ///
  /// Unlike the reclaim path, this one swallows failures into `null`. A
  /// storage report is a read-only diagnostic that has to render on a
  /// half-broken deployment — an unattached schema or a file that does not
  /// exist yet must show as "unknown", not take the whole screen down.
  Future<int?> _schemaPragmaInt(String schema, String pragma) async {
    try {
      final result = await _resqlite.transaction(
        (tx) => tx.execute('PRAGMA "$schema".$pragma', const []),
      );
      return _sqlInt(result.rows.singleOrNull?.singleOrNull);
    } catch (_) {
      return null;
    }
  }

  /// Measures one SQLite file: what it occupies, and how much of that is dead.
  Future<StorageDatabaseFile> _storageDatabaseFile({
    required String path,
    required String schema,
    required int? capBytes,
  }) async {
    final file = fs.file(path);
    final wal = fs.file('$path-wal');

    final pageSize = await _schemaPragmaInt(schema, 'page_size');
    final freelist = await _schemaPragmaInt(schema, 'freelist_count');

    return StorageDatabaseFile(
      name: fs.path.basename(path),
      // Absolute, because the payload promises absolute and because the
      // configured value is not one: `Settings.load()` joins onto a null
      // basePath in production, so this arrives as `.zonai/data/zonai.sqlite`
      // -- a path that only resolves if you already know the server's working
      // directory, which is exactly what an operator reading it does not.
      path: file.absolute.path,
      sizeBytes: file.existsSync() ? file.lengthSync() : 0,
      walBytes: wal.existsSync() ? wal.lengthSync() : 0,
      // Both halves or neither: a page size without a freelist count says
      // nothing about reclaimable space, and multiplying by a guessed zero
      // would report "nothing to reclaim" for a file that was never read.
      reclaimableBytes: pageSize == null || freelist == null
          ? null
          : freelist * pageSize,
      capBytes: capBytes,
    );
  }

  /// Total bytes and file count under [directory], walking it recursively.
  ///
  /// A missing directory is `(0, 0)` rather than an error: a deployment that
  /// has never accepted a photo has no images directory, and that is not a
  /// fault to report.
  (int bytes, int files) _directoryUsage(String directory) {
    final dir = fs.directory(directory);
    if (!dir.existsSync()) return (0, 0);

    var bytes = 0;
    var files = 0;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        bytes += entity.lengthSync();
        files++;
      } catch (_) {
        // A file that vanished between the listing and the stat, or one this
        // process cannot read. Skipping it under-reports by one file, which
        // is the right direction for a diagnostic that must not throw.
      }
    }
    return (bytes, files);
  }

  /// Rows in [table], or `null` when it cannot be counted.
  ///
  /// Unqualified on purpose: the disposable tables live in attached files and
  /// resolve there because `main` no longer has a table by those names (see
  /// `_ensureDisposableTables`). A table that has not been created yet
  /// answers `null` — unknown — rather than `0`.
  Future<int?> _tableRowCount(Raindrop db, String table) async {
    try {
      final result = await db.execute(
        'SELECT COUNT(*) FROM "$table"',
        const [],
      );
      return _sqlInt(result.rows.firstOrNull?.firstOrNull);
    } catch (_) {
      return null;
    }
  }

  /// How much space zonai is using, and how much is left.
  ///
  /// Expensive by the standards of the dashboard's metrics poll — it shells
  /// out to `df`, walks the photos directory, and makes two pragma round
  /// trips per database file — which is why this is its own endpoint behind
  /// its own screen rather than another field on [DashboardMetrics].
  Future<StorageMetrics> _storageMetrics({required Jwt jwt}) async {
    if (!jwt.admin.isAdmin) {
      throw const TableAccessDeniedException(
        table: '_storage',
        operation: 'metrics',
      );
    }

    final db = await open();

    // Schemas in the same order as `zonaiSqlitePaths`, application database
    // first. Kept as a parallel list rather than a map so the two cannot
    // drift into a different order than the paths they describe.
    const schemas = ['main', kLogDbSchema, kRateLimitDbSchema];
    final paths = settings.zonaiSqlitePaths;

    final databases = <StorageDatabaseFile>[];
    for (var i = 0; i < paths.length && i < schemas.length; i++) {
      databases.add(
        await _storageDatabaseFile(
          path: paths[i],
          schema: schemas[i],
          // Only the log database can carry a cap today, and only when the
          // project sets one.
          capBytes: schemas[i] == kLogDbSchema
              ? settings.logDatabaseMaxBytes
              : null,
        ),
      );
    }

    final tables = <StorageTableRows>[];
    for (final table in InternalDbArtifacts.tableNames) {
      tables.add(
        StorageTableRows(
          table: table,
          rowCount: await _tableRowCount(db, table),
        ),
      );
    }

    final (photosBytes, photosFileCount) = _directoryUsage(settings.imagesPath);

    return StorageMetrics(
      databases: databases,
      photosBytes: photosBytes,
      photosFileCount: photosFileCount,
      tables: tables,
      // `null` is unknown, not zero (see [freeDiskBytes]). Passed straight
      // through so the UI can say "unknown" — collapsing it to 0 here would
      // report a full disk on every platform whose `df` we cannot parse.
      freeDiskBytes: await freeDiskBytes(fs.directory(settings.dataPath).path),
    );
  }
}
