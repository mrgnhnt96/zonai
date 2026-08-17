/// One SQLite file zonai owns, measured on disk.
///
/// [sizeBytes] and [reclaimableBytes] are deliberately separate numbers rather
/// than one total. A file is only as large as its live pages plus its
/// freelist, and those two halves call for opposite responses: growth in the
/// live half means the data really is that big, growth in the freelist means a
/// rewrite would hand the space back. "3.2 GB on disk, 2.1 GB of it dead" is
/// the sentence an operator can act on; the sum alone is the one that reads as
/// "buy a bigger disk".
class StorageDatabaseFile {
  const StorageDatabaseFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.walBytes,
    this.reclaimableBytes,
    this.capBytes,
  });

  /// The file's basename, e.g. `zonai_log.sqlite`.
  final String name;

  /// Absolute path, so an operator can go and look at the file themselves.
  final String path;

  /// Size of the database file, or `0` when it does not exist yet.
  final int sizeBytes;

  /// Size of the `-wal` sidecar, or `0` when there is none.
  ///
  /// Counted separately because it is real occupied space that `ls` on the
  /// database file alone does not show, and because a WAL that keeps growing
  /// is its own diagnosis (a reader holding a snapshot open) rather than more
  /// of the same.
  final int walBytes;

  /// Bytes on this file's freelist — free *inside* the file, not returned to
  /// the operating system — or `null` when the pragmas could not be read.
  ///
  /// `null` is unknown, never zero: a file whose freelist cannot be read and
  /// a file with nothing on its freelist are opposite situations, and showing
  /// the first as "0 B reclaimable" would tell an operator there is nothing
  /// to recover at exactly the moment they are looking for space.
  ///
  /// **This can legitimately exceed [sizeBytes].** `freelist_count` describes
  /// the *logical* database — the main file plus whatever is still in its
  /// uncheckpointed WAL — while [sizeBytes] is only the main file. Measured on
  /// a freshly created database: a 4 KB main file, a 288 KB WAL, and 28 KB on
  /// the freelist. The bound that always holds is
  /// `reclaimableBytes <= sizeBytes + walBytes`, so anything comparing the two
  /// must include the sidecar.
  final int? reclaimableBytes;

  /// The configured ceiling on this file, or `null` where none is set.
  ///
  /// Only the log database can carry one today (`logDatabaseMaxBytes`), and
  /// only when the project configures it — so `null` here means "uncapped",
  /// which is a different thing from a cap of zero.
  final int? capBytes;

  factory StorageDatabaseFile.fromJson(Map<String, dynamic> json) {
    return StorageDatabaseFile(
      name: json['name'] as String,
      path: json['path'] as String,
      sizeBytes: json['size_bytes'] as int,
      walBytes: json['wal_bytes'] as int,
      reclaimableBytes: json['reclaimable_bytes'] as int?,
      capBytes: json['cap_bytes'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'size_bytes': sizeBytes,
    'wal_bytes': walBytes,
    'reclaimable_bytes': reclaimableBytes,
    'cap_bytes': capBytes,
  };
}

/// Row count for one internal table.
///
/// These are the counts the dashboard's Tables panel cannot show: it filters
/// `_`-prefixed tables out, which is why `_log` reaching 4.6M rows and filling
/// a 1 GB production volume (2026-08-13) was invisible until the disk was
/// gone.
class StorageTableRows {
  const StorageTableRows({required this.table, required this.rowCount});

  /// The table's SQLite name, e.g. `_log`.
  final String table;

  /// Rows in the table, or `null` when it could not be counted — a table that
  /// has not been created yet reads as unknown rather than as empty.
  final int? rowCount;

  factory StorageTableRows.fromJson(Map<String, dynamic> json) {
    return StorageTableRows(
      table: json['table'] as String,
      rowCount: json['row_count'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {'table': table, 'row_count': rowCount};
}

/// How much space zonai is using, and how much is left.
class StorageMetrics {
  const StorageMetrics({
    required this.databases,
    required this.photosBytes,
    required this.photosFileCount,
    required this.tables,
    this.freeDiskBytes,
  });

  /// Every SQLite file zonai owns, application database first.
  final List<StorageDatabaseFile> databases;

  /// Total bytes under the photos directory.
  final int photosBytes;

  /// How many files that total is spread across.
  final int photosFileCount;

  /// Row counts for the internal tables, in the order they were asked for.
  final List<StorageTableRows> tables;

  /// Bytes available on the volume holding the data directory, or `null` when
  /// it cannot be determined.
  ///
  /// **`null` is unknown, never zero.** An unparsed `df` and a full disk are
  /// opposite situations (see `freeDiskBytes`), and a UI that renders the
  /// first as "0 B free" is reporting an emergency that is not happening —
  /// while hiding that it does not actually know.
  final int? freeDiskBytes;

  /// Total bytes across every database file and its WAL.
  int get totalDatabaseBytes {
    var total = 0;
    for (final db in databases) {
      total += db.sizeBytes + db.walBytes;
    }
    return total;
  }

  /// Total reclaimable bytes across the files that could be read.
  ///
  /// Files whose freelist is unknown contribute nothing rather than being
  /// guessed at, so this is a floor on what a rewrite would recover.
  int get totalReclaimableBytes {
    var total = 0;
    for (final db in databases) {
      total += db.reclaimableBytes ?? 0;
    }
    return total;
  }

  factory StorageMetrics.fromJson(Map<String, dynamic> json) {
    return StorageMetrics(
      databases: [
        for (final db in json['databases'] as List)
          StorageDatabaseFile.fromJson(Map<String, dynamic>.from(db as Map)),
      ],
      photosBytes: json['photos_bytes'] as int,
      photosFileCount: json['photos_file_count'] as int,
      tables: [
        for (final table in json['tables'] as List)
          StorageTableRows.fromJson(Map<String, dynamic>.from(table as Map)),
      ],
      freeDiskBytes: json['free_disk_bytes'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'databases': [for (final db in databases) db.toJson()],
    'photos_bytes': photosBytes,
    'photos_file_count': photosFileCount,
    'tables': [for (final table in tables) table.toJson()],
    'free_disk_bytes': freeDiskBytes,
  };
}
