part of zonai_db;

const _dashboardRequestLogHourMs = 3600000;

final _requestDurationRe = RegExp(r'^\[\d+\] (\d+)ms:');

extension _DashboardMetricsX on ZonaiDb {
  Future<DashboardMetrics> _dashboardMetrics({
    required Jwt jwt,
    int? since,
    bool excludeAdmin = false,
  }) async {
    if (!jwt.admin.isAdmin) {
      throw const TableAccessDeniedException(
        table: '_dashboard',
        operation: 'metrics',
      );
    }

    final windowSince = since ?? _dashboardRequestLogSinceMs();
    // Epoch **milliseconds**, which is what `DateTimeTransformer` writes for
    // every `dateTime` column (see raindrop_sqlite's `date_time.dart`). This
    // used to be `~/ 1000`, comparing a seconds value against a milliseconds
    // column: every `_jwt` row read as active, because any stored millisecond
    // timestamp is ~1000x a current seconds one. That reported the whole
    // un-swept table -- `_delete_expired_jwts` only runs at 04:00 -- as people
    // signed in.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final hourFromNowMs = nowMs + _dashboardRequestLogHourMs;
    final db = await open();
    final adminFilter = excludeAdmin ? ' AND is_admin = 0' : '';

    // Grouped into three records only because `.wait` on a record tops out
    // below the number of queries this needs. Every future is constructed
    // before the first await, so all nine still run concurrently -- the shape
    // to preserve here is "one concurrent batch", not "one record".
    //
    // `since` and `excludeAdmin` scope the `_log` group alone. The push queue
    // and the session counts are current state rather than a window over
    // request history, so filtering them by a request-log window would answer a
    // question nobody asked.
    final (
      (bucketResult, requestCountResult, errorCountResult, messagesResult),
      (sessionsResult, sessionUsersResult),
      (pushStatusResult, pushFailedResult, lastDrainResult),
    ) = await (
      (
        db.execute(
          '''
            SELECT ((timestamp - ?) / ?) AS bucket_index, COUNT(*) AS count
            FROM "_log"
            WHERE level = 'request' AND timestamp >= ?$adminFilter
            GROUP BY bucket_index
            HAVING bucket_index >= 0 AND bucket_index < 24
            ''',
          [windowSince, _dashboardRequestLogHourMs, windowSince],
        ),
        db.execute(
          '''
            SELECT COUNT(*) AS count
            FROM "_log"
            WHERE level = 'request' AND timestamp >= ?$adminFilter
            ''',
          [windowSince],
        ),
        db.execute(
          '''
            SELECT COUNT(*) AS count
            FROM "_log"
            WHERE level = 'error' AND timestamp >= ?$adminFilter
            ''',
          [windowSince],
        ),
        db.execute(
          '''
            SELECT message
            FROM "_log"
            WHERE level = 'request' AND timestamp >= ?$adminFilter
            ''',
          [windowSince],
        ),
      ).wait,
      (
        // Active, expiring-soon and distinct-user counts in one pass, so the
        // three can never disagree about which rows are live.
        db.execute(
          '''
            SELECT COUNT(*) AS active,
                   SUM(CASE WHEN expires_at <= ? THEN 1 ELSE 0 END) AS expiring,
                   COUNT(DISTINCT user_id) AS users
            FROM "_jwt"
            WHERE expires_at > ?
            ''',
          [hourFromNowMs, nowMs],
        ),
        db.execute(
          '''
            SELECT user_id, COUNT(*) AS session_count
            FROM "_jwt"
            WHERE expires_at > ?
            GROUP BY user_id
            ORDER BY session_count DESC
            LIMIT ?
            ''',
          [nowMs, _dashboardTopSessionUsers],
        ),
      ).wait,
      (
        // Depth and the recipient counters together: grouping by status gives
        // both, and one pass cannot report a depth from a different instant
        // than the sums.
        db.execute('''
            SELECT status,
                   COUNT(*) AS count,
                   SUM(delivered) AS delivered,
                   SUM(permanently_rejected) AS permanently_rejected,
                   SUM(transiently_failed) AS transiently_failed
            FROM "_push_jobs"
            GROUP BY status
            ''', const []),
        db.execute(
          '''
            SELECT id, error, delivered, created_at, updated_at
            FROM "_push_jobs"
            WHERE status = ?
            ORDER BY updated_at DESC
            LIMIT ?
            ''',
          [PushJobStatus.failed.name, _dashboardFailedPushJobs],
        ),
        // The drain records no counts of its own -- see [DashboardDrainRun] --
        // so this is the whole of what the last run left behind.
        db.execute(
          '''
            SELECT started, completed, failed, error
            FROM "_cron_jobs"
            WHERE name = ?
            ORDER BY started DESC
            LIMIT 1
            ''',
          const [_dashboardDrainCronName],
        ),
      ).wait,
    ).wait;

    final bucketCounts = List<int>.filled(24, 0);
    for (final row in bucketResult.rows) {
      if (row.length < 2) continue;
      final index = _sqlInt(row[0]);
      final count = _sqlInt(row[1]);
      if (index != null && count != null && index >= 0 && index < 24) {
        bucketCounts[index] = count;
      }
    }

    final requestBuckets = [
      for (var i = 0; i < 24; i++)
        {
          'hour': windowSince + i * _dashboardRequestLogHourMs,
          'count': bucketCounts[i],
        },
    ];

    final messages = [
      for (final row in messagesResult.rows)
        if (row.isNotEmpty && row.first is String) row.first as String,
    ];

    final sessions = _dashboardSessions(
      sessionsResult.rows,
      sessionUsersResult.rows,
    );
    final pushQueue = _dashboardPushQueue(
      pushStatusResult.rows,
      pushFailedResult.rows,
      lastDrainResult.rows,
    );

    return DashboardMetrics(
      // From `sessions`, not a query of its own: two counts of the same thing
      // are two chances to disagree.
      activeSessions: sessions.active,
      errorCount24h:
          _sqlInt(errorCountResult.rows.firstOrNull?.firstOrNull) ?? 0,
      p95ResponseMs: _computeP95(messages),
      requestCount24h:
          _sqlInt(requestCountResult.rows.firstOrNull?.firstOrNull) ?? 0,
      requestBuckets: [
        for (final bucket in requestBuckets)
          DashboardRequestBucket.fromJson(bucket),
      ],
      pushQueue: pushQueue,
      sessions: sessions,
    );
  }
}

/// The cron whose queue the push panel shows. Matched by name because
/// `_cron_jobs` is keyed by it, and `DrainPushJobsCron` lives in `zonai_schema`
/// where the engine cannot reach its instance.
const _dashboardDrainCronName = '_drain_push_jobs';

/// Enough failed jobs to see a pattern, few enough that a queue that has been
/// failing for a week does not ship its whole history in a metrics response.
const _dashboardFailedPushJobs = 20;

const _dashboardTopSessionUsers = 5;

DashboardSessions _dashboardSessions(
  List<List<Object?>> countsRows,
  List<List<Object?>> userRows,
) {
  final counts = countsRows.firstOrNull;

  return DashboardSessions(
    active: _sqlInt(counts?.elementAtOrNull(0)) ?? 0,
    // `SUM` over no rows is NULL, which is zero expiring rather than unknown --
    // the `WHERE` already established there are no live sessions at all.
    expiringWithinHour: _sqlInt(counts?.elementAtOrNull(1)) ?? 0,
    distinctUsers: _sqlInt(counts?.elementAtOrNull(2)) ?? 0,
    topUsers: [
      for (final row in userRows)
        if (_sqlString(row.elementAtOrNull(0)) case final userId?)
          DashboardSessionUser(
            userId: userId,
            sessionCount: _sqlInt(row.elementAtOrNull(1)) ?? 0,
          ),
    ],
  );
}

DashboardPushQueue _dashboardPushQueue(
  List<List<Object?>> statusRows,
  List<List<Object?>> failedRows,
  List<List<Object?>> lastDrainRows,
) {
  final depth = <String, int>{};
  var delivered = 0;
  var permanentlyRejected = 0;
  var transientlyFailed = 0;

  for (final row in statusRows) {
    final status = _sqlString(row.elementAtOrNull(0));
    if (status == null) continue;
    depth[status] = _sqlInt(row.elementAtOrNull(1)) ?? 0;
    delivered += _sqlInt(row.elementAtOrNull(2)) ?? 0;
    permanentlyRejected += _sqlInt(row.elementAtOrNull(3)) ?? 0;
    transientlyFailed += _sqlInt(row.elementAtOrNull(4)) ?? 0;
  }

  final drainRow = lastDrainRows.firstOrNull;

  return DashboardPushQueue(
    pending: depth[PushJobStatus.pending.name] ?? 0,
    running: depth[PushJobStatus.running.name] ?? 0,
    completed: depth[PushJobStatus.completed.name] ?? 0,
    failed: depth[PushJobStatus.failed.name] ?? 0,
    delivered: delivered,
    permanentlyRejected: permanentlyRejected,
    transientlyFailed: transientlyFailed,
    failedJobs: [
      for (final row in failedRows)
        if (_sqlString(row.elementAtOrNull(0)) case final id?)
          DashboardPushFailure(
            id: id,
            error: _sqlString(row.elementAtOrNull(1)),
            delivered: _sqlInt(row.elementAtOrNull(2)) ?? 0,
            createdAt: _sqlDateTime(row.elementAtOrNull(3)),
            updatedAt: _sqlDateTime(row.elementAtOrNull(4)),
          ),
    ],
    // A drain that has never run is null, not a synthetic run at the epoch:
    // "never drained" and "drained in 1970" would render the same and mean
    // opposite things.
    lastDrain: switch (_sqlInt(drainRow?.elementAtOrNull(0))) {
      final startedMs? => DashboardDrainRun(
        startedAt: DateTime.fromMillisecondsSinceEpoch(startedMs),
        completedAt: switch (_sqlInt(drainRow?.elementAtOrNull(1))) {
          final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
          _ => null,
        },
        failedAt: switch (_sqlInt(drainRow?.elementAtOrNull(2))) {
          final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
          _ => null,
        },
        error: _sqlString(drainRow?.elementAtOrNull(3)),
      ),
      _ => null,
    },
  );
}

int _dashboardRequestLogSinceMs() {
  final now = DateTime.now();
  final nowHourMs =
      now.millisecondsSinceEpoch -
      (now.millisecondsSinceEpoch % _dashboardRequestLogHourMs);
  return nowHourMs - 23 * _dashboardRequestLogHourMs;
}

int? _sqlInt(Object? value) => switch (value) {
  final int v => v,
  final BigInt v => v.toInt(),
  final double v => v.toInt(),
  _ => null,
};

String? _sqlString(Object? value) => value is String ? value : null;

/// A `dateTime` column, which raindrop stores as epoch milliseconds.
///
/// Falls back to the epoch for a value that is not an integer at all. The
/// columns this reads are `NOT NULL`, so reaching the fallback means the row is
/// malformed -- and a wrong timestamp on a failed job is a better outcome than
/// dropping the job's error message out of the panel entirely.
DateTime _sqlDateTime(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch(_sqlInt(value) ?? 0);

int? _computeP95(List<String> messages) {
  final durations = <int>[];
  for (final message in messages) {
    final match = _requestDurationRe.firstMatch(message);
    if (match == null) continue;
    final duration = int.tryParse(match.group(1)!);
    if (duration != null) durations.add(duration);
  }
  if (durations.isEmpty) return null;
  durations.sort();
  return durations[((durations.length - 1) * 0.95).round()];
}
