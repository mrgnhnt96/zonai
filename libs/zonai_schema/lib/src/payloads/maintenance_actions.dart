/// Wire formats for the Maintenance screen's cleanup actions.
///
/// Every one of these wraps a verb that already exists on `ZonaiDb`. Nothing
/// here decides *what* a cleanup does — it decides what the operator is told
/// afterwards, which is the part the engine cannot do on its own.
library;

/// Internal tables a bulk purge is allowed to empty.
///
/// A mirror of the engine's `_purgeableTables`, and deliberately a written-out
/// constant rather than `InternalDbArtifacts.tableNames.difference(...)`: that
/// set lives behind an import chain that reaches Raindrop's column builders
/// and, through them, native SQLite. `payloads.dart` is the library `apps/web`
/// compiles to JavaScript, so importing it here would break the browser build
/// for the sake of one set of strings.
///
/// The cost of writing it out is drift, so drift is what the test pins:
/// `maintenance_purgeable_tables_test.dart` asserts this equals the engine's
/// derivation, and fails the moment a new internal table is added. The engine
/// remains the authority — this is the copy the UI reads.
///
/// **`_photos` is absent on purpose and must stay absent.** Deleting a photo
/// row also deletes the file behind it, through a per-row path a bulk `DELETE`
/// has no hook for; purging the table would orphan every file it removed a row
/// for. Photos are cleaned by [PhotoCleanupResult]'s verb instead, one row at
/// a time.
/// **`_api_tokens` is present on purpose.** Purging it revokes every API
/// token at once, which is the break-glass answer to a suspected leak and is
/// no more drastic than purging `_jwt`, which signs out every user. Deleting
/// the row *is* the complete revocation -- unlike `_photos`, nothing outside
/// the database is left behind.
/// **`_password_reset_requirements` is present, and it is the one entry whose
/// purge is a *weakening*.** Every other table here becomes more restrictive
/// when emptied -- purging `_jwt` signs everyone out, purging `_api_tokens`
/// revokes every token. Purging this one lifts a control: every account an
/// operator forced to choose a new password is quietly released, and the
/// password each was forced away from keeps working. It stays purgeable
/// because the derivation admits every internal table but `_photos` and a
/// hand-carved exception would drift, but an operator reaching for it should
/// know it is an amnesty, not a cleanup.
const kPurgeableTableNames = <String>{
  '_abusers',
  '_api_tokens',
  '_auth_challenges',
  '_cron_jobs',
  '_jwt',
  '_log',
  '_oauth_identities',
  '_password_reset_requirements',
  '_push_jobs',
  '_rate_limit',
};

/// Which log rows to delete.
class PurgeLogsBody {
  const PurgeLogsBody({this.olderThanDays});

  /// Delete log rows older than this many days, or every row when `null`.
  ///
  /// Nullable rather than defaulted to zero: "everything" and "nothing older
  /// than today" are different requests, and a default would silently turn
  /// the destructive one into the routine one — or the reverse.
  final int? olderThanDays;

  factory PurgeLogsBody.fromJson(Map<String, dynamic> json) {
    return PurgeLogsBody(olderThanDays: json['older_than_days'] as int?);
  }

  Map<String, dynamic> toJson() => {'older_than_days': olderThanDays};
}

/// Which internal table to empty.
class PurgeTableBody {
  const PurgeTableBody({required this.table});

  /// Must be one of [kPurgeableTableNames]. Checked server-side regardless —
  /// the engine refuses an unlisted table itself, and this body arrives from
  /// a browser.
  final String table;

  factory PurgeTableBody.fromJson(Map<String, dynamic> json) {
    return PurgeTableBody(table: json['table'] as String);
  }

  Map<String, dynamic> toJson() => {'table': table};
}

/// How many rows a purge actually removed.
///
/// The number is the whole point: a purge that matched nothing and a purge
/// that drained four million rows both "succeed", and only this tells them
/// apart.
class MaintenanceRowsResult {
  const MaintenanceRowsResult({required this.rowsAffected});

  final int rowsAffected;

  factory MaintenanceRowsResult.fromJson(Map<String, dynamic> json) {
    return MaintenanceRowsResult(rowsAffected: json['rows_affected'] as int);
  }

  Map<String, dynamic> toJson() => {'rows_affected': rowsAffected};
}

/// How many photo files the unreferenced-photo sweep deleted.
class PhotoCleanupResult {
  const PhotoCleanupResult({required this.deletedCount});

  final int deletedCount;

  factory PhotoCleanupResult.fromJson(Map<String, dynamic> json) {
    return PhotoCleanupResult(deletedCount: json['deleted_count'] as int);
  }

  Map<String, dynamic> toJson() => {'deleted_count': deletedCount};
}

/// What one attempt to reclaim log-database space did.
///
/// The wire mirror of the engine's `LogSpaceReclamation` record, field for
/// field — including [skipped], which is the field this payload exists to
/// carry.
class LogSpaceReclamationResult {
  const LogSpaceReclamationResult({
    required this.reclaimableBytes,
    required this.reclaimedBytes,
    required this.vacuumed,
    this.skipped,
  });

  /// Bytes on the log database's freelist when the attempt started — free
  /// *inside* the file, not returned to the operating system.
  final int reclaimableBytes;

  /// Bytes the file actually shrank by. Zero when nothing was rewritten.
  final int reclaimedBytes;

  /// Whether the rewrite ran at all.
  final bool vacuumed;

  /// Why nothing was rewritten, or `null` when the attempt was not blocked.
  ///
  /// **Render this verbatim; do not collapse it to a boolean.** A deployment
  /// whose volume is already full fails the headroom check and reclaims
  /// nothing — and that is exactly the deployment where a silent success is
  /// worst, because it is indistinguishable from having had nothing to
  /// reclaim. Separating those two is the only reason this string exists.
  ///
  /// Note that `null` here covers both "it rewrote the file" and the ordinary
  /// "there was not enough dead space to be worth it" — neither is a problem
  /// to report. [vacuumed] tells those two apart.
  final String? skipped;

  factory LogSpaceReclamationResult.fromJson(Map<String, dynamic> json) {
    return LogSpaceReclamationResult(
      reclaimableBytes: json['reclaimable_bytes'] as int,
      reclaimedBytes: json['reclaimed_bytes'] as int,
      vacuumed: json['vacuumed'] as bool,
      skipped: json['skipped'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'reclaimable_bytes': reclaimableBytes,
    'reclaimed_bytes': reclaimedBytes,
    'vacuumed': vacuumed,
    'skipped': skipped,
  };
}
