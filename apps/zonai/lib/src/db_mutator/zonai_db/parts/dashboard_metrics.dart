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
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final db = await open();
    final adminFilter = excludeAdmin ? ' AND is_admin = 0' : '';

    final (
      bucketResult,
      requestCountResult,
      errorCountResult,
      sessionsResult,
      messagesResult,
    ) = await (
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
            SELECT COUNT(*) AS count
            FROM "_jwt"
            WHERE expires_at > ?
            ''',
        [nowSeconds],
      ),
      db.execute(
        '''
            SELECT message
            FROM "_log"
            WHERE level = 'request' AND timestamp >= ?$adminFilter
            ''',
        [windowSince],
      ),
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

    return DashboardMetrics(
      activeSessions:
          _sqlInt(sessionsResult.rows.firstOrNull?.firstOrNull) ?? 0,
      errorCount24h:
          _sqlInt(errorCountResult.rows.firstOrNull?.firstOrNull) ?? 0,
      p95ResponseMs: _computeP95(messages),
      requestCount24h:
          _sqlInt(requestCountResult.rows.firstOrNull?.firstOrNull) ?? 0,
      requestBuckets: [
        for (final bucket in requestBuckets)
          DashboardRequestBucket.fromJson(bucket),
      ],
    );
  }
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
