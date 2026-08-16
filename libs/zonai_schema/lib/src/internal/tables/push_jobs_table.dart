import 'dart:convert';

import 'package:zonai_schema/zonai_schema.dart';

/// Where a fan-out is in its life.
///
/// [running] is not "a process is working on it right now" — nothing here
/// holds a lock. It means a drain has claimed the job and committed at least
/// one batch. A crash leaves the row in [running] with a cursor, which is
/// exactly what the next drain needs to resume.
enum PushJobStatus { pending, running, completed, failed }

/// One recorded fan-out.
///
/// The row exists because checkpointing needs it: the cursor has to survive a
/// restart. Handing its key back from `push` was then free, and it is what
/// gives an app progress, counts and failure reasons through an ordinary
/// query rather than a receipts table nobody asked for (§3).
class PushJobEntry {
  PushJobEntry({
    required this.id,
    required this.message,
    required this.targetTable,
    required this.targetColumn,
    required this.platformColumn,
    required this.whereJson,
    required this.cursor,
    required this.status,
    required this.delivered,
    required this.permanentlyRejected,
    required this.transientlyFailed,
    required this.error,
    required this.createdAt,
    required this.updatedAt,
  });

  PushJobEntry.create({
    required PushMessage message,
    required this.targetTable,
    required this.targetColumn,
    required Where? where,
    this.platformColumn,
  }) : id = PushJobId.generate(),
       message = jsonEncode(message.toJson()),
       whereJson = where == null ? null : jsonEncode(where.toJson()),
       cursor = null,
       status = PushJobStatus.pending,
       delivered = 0,
       permanentlyRejected = 0,
       transientlyFailed = 0,
       error = null,
       createdAt = DateTime.now(),
       updatedAt = DateTime.now();

  final PushJobId id;

  /// The [PushMessage], JSON-encoded. Stored rather than referenced so a
  /// resumed job sends what was enqueued, not what the code says today.
  final String message;

  final String targetTable;
  final String targetColumn;

  /// The column holding each row's `DevicePlatform`, when the app named one.
  ///
  /// Stored on the job rather than resolved at drain time because a fan-out
  /// outlives the request that started it: a job resumed after a restart has
  /// only this row to work from, and routing every recipient to FCM because
  /// the column name was forgotten would deliver iOS notifications through a
  /// transport the app may not even have configured.
  final String? platformColumn;

  /// The caller's `Where`, JSON-encoded, or null for "every row with a
  /// non-null token".
  final String? whereJson;

  /// The last primary key whose batch was committed. Null before the first
  /// batch. Keyset pagination resumes at `pk > cursor`, which is why this is
  /// a key and not an offset — an offset silently skips or repeats rows when
  /// devices register mid-scan, and they will.
  final String? cursor;

  final PushJobStatus status;

  final int delivered;
  final int permanentlyRejected;
  final int transientlyFailed;

  /// Why the job stopped, when [status] is [PushJobStatus.failed].
  final String? error;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// The stored message, decoded.
  PushMessage get pushMessage =>
      PushMessage.fromJson(jsonDecode(message) as Map<String, dynamic>);

  /// The stored predicate, decoded, or null when the job targets every row.
  Where? get where => switch (whereJson) {
    null => null,
    final json => Where.fromJson(jsonDecode(json) as Map<String, dynamic>),
  };
}

class PushJobsTable extends Table<PushJobEntry> {
  PushJobsTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PushJobId.new,
        generate: PushJobId.generate,
      ),
      message = $.text('message', (s) => s.message),
      targetTable = $.text('target_table', (s) => s.targetTable),
      targetColumn = $.text('target_column', (s) => s.targetColumn),
      platformColumn = $.text('platform_column', (s) => s.platformColumn),
      whereJson = $.text('where_json', (s) => s.whereJson),
      cursor = $.text('cursor', (s) => s.cursor),
      status = $.enumerator('status', PushJobStatus.values, (s) => s.status),
      delivered = $.integer('delivered', (s) => s.delivered, defaultValue: 0),
      permanentlyRejected = $.integer(
        'permanently_rejected',
        (s) => s.permanentlyRejected,
        defaultValue: 0,
      ),
      transientlyFailed = $.integer(
        'transiently_failed',
        (s) => s.transientlyFailed,
        defaultValue: 0,
      ),
      error = $.text('error', (s) => s.error),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  PushJobEntry fromRow(RowReader read) {
    return PushJobEntry(
      id: read(id),
      message: read(message),
      targetTable: read(targetTable),
      targetColumn: read(targetColumn),
      platformColumn: read(platformColumn),
      whereJson: read(whereJson),
      cursor: read(cursor),
      status: read(status),
      delivered: read(delivered),
      permanentlyRejected: read(permanentlyRejected),
      transientlyFailed: read(transientlyFailed),
      error: read(error),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<PushJobId> id;
  final TextColumn message;
  final TextColumn targetTable;
  final TextColumn targetColumn;
  final ColumnType<String?> platformColumn;
  final ColumnType<String?> whereJson;
  final ColumnType<String?> cursor;
  final EnumColumn<PushJobStatus> status;
  final IntColumn delivered;
  final IntColumn permanentlyRejected;
  final IntColumn transientlyFailed;
  final ColumnType<String?> error;
  final DateTimeColumn createdAt;
  final DateTimeColumn updatedAt;
}

final pushJobs = table('_push_jobs', PushJobsTable.new, (table) {
  uniqueIndex('push_job_id_unique').on(table.id);
  // The drain's only query: the oldest job not yet finished. Without this it
  // is a full scan of a table that grows by one row per send.
  index('push_job_status_created_index').on(table.status, table.createdAt);
});
