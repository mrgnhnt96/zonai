import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

import '../api/dashboard_client.dart';
import '../utils/sqlite_table_utils.dart';
import 'sqlite_tables_provider.dart';

// ── Models ────────────────────────────────────────────────────────────────────

final class DashboardStats {
  const DashboardStats({
    required this.requestCount24h,
    required this.errorCount24h,
    required this.activeSessions,
    required this.p95ResponseMs,
  });

  final int requestCount24h;
  final int errorCount24h;
  final int activeSessions;
  final int? p95ResponseMs;

  double? get errorRate => requestCount24h == 0 ? null : errorCount24h / requestCount24h * 100;
}

final class RequestBucket {
  const RequestBucket({required this.hour, required this.count});
  final DateTime hour;
  final int count;
}

final class TopError {
  const TopError({required this.message, required this.count, required this.lastSeen, this.detail});
  final String message;
  final int count;
  final DateTime lastSeen;
  // The `error` column from the most recent occurrence (stack trace / details).
  final String? detail;
}

final class CronJobSummary {
  const CronJobSummary({
    required this.name,
    required this.lastStarted,
    this.lastCompleted,
    this.lastFailed,
    this.lastError,
  });

  final String name;
  final DateTime lastStarted;
  final DateTime? lastCompleted;
  final DateTime? lastFailed;
  final String? lastError;

  bool get succeeded => lastCompleted != null && lastFailed == null;
  bool get failed => lastFailed != null;

  Duration? get duration {
    if (lastCompleted == null) return null;
    return lastCompleted!.difference(lastStarted);
  }
}

final class DashboardMetrics {
  const DashboardMetrics({required this.stats, required this.buckets});

  final DashboardStats stats;
  final List<RequestBucket> buckets;
}

// ── Providers ─────────────────────────────────────────────────────────────────

final dashboardMetricsProvider = AsyncNotifierProvider<_DashboardMetricsNotifier, DashboardMetrics>(
  _DashboardMetricsNotifier.new,
);

final topErrorsProvider = AsyncNotifierProvider<_TopErrorsNotifier, List<TopError>>(_TopErrorsNotifier.new);

// Tracks which error message is currently expanded (null = none).
final expandedErrorProvider = NotifierProvider<_ExpandedErrorNotifier, String?>(_ExpandedErrorNotifier.new);

final cronJobsProvider = AsyncNotifierProvider<_CronJobsNotifier, List<CronJobSummary>>(_CronJobsNotifier.new);

final tableCountsProvider = AsyncNotifierProvider<_TableCountsNotifier, Map<String, int>>(_TableCountsNotifier.new);

// ── Implementations ────────────────────────────────────────────────────────────

class _DashboardMetricsNotifier extends AsyncNotifier<DashboardMetrics> {
  @override
  Future<DashboardMetrics> build() async {
    if (!ref.binding.isClient) {
      return DashboardMetrics(
        stats: const DashboardStats(requestCount24h: 0, errorCount24h: 0, activeSessions: 0, p95ResponseMs: null),
        buckets: const [],
      );
    }

    final since = _requestLogSinceMs();
    final data = await fetchDashboardMetrics(since: since);

    return DashboardMetrics(
      stats: DashboardStats(
        requestCount24h: data.requestCount24h,
        errorCount24h: data.errorCount24h,
        activeSessions: data.activeSessions,
        p95ResponseMs: data.p95ResponseMs,
      ),
      buckets: [
        for (final bucket in data.requestBuckets)
          RequestBucket(hour: DateTime.fromMillisecondsSinceEpoch(bucket.hour), count: bucket.count),
      ],
    );
  }
}

class _TopErrorsNotifier extends AsyncNotifier<List<TopError>> {
  @override
  Future<List<TopError>> build() async {
    if (!ref.binding.isClient) return const [];

    final since = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;

    final data = await revaliServer.db.list(
      body: ListBody(
        table: '_log',
        where: And([Eq('level', 'error'), Gt('timestamp', since)]),
        limit: 500,
        orderBy: [const OrderByTerm(column: 'timestamp', direction: SortDirection.desc)],
      ),
    );

    // Group by message; items are DESC by timestamp so first occurrence = most recent.
    final groups = <String, ({int count, DateTime lastSeen, String? detail})>{};

    for (final item in _parseItems(data)) {
      final message = item['message'];
      if (message is! String || message.isEmpty) continue;
      final ts = _parseTimestamp(item['timestamp']) ?? DateTime.now();
      final existing = groups[message];
      if (existing == null) {
        groups[message] = (count: 1, lastSeen: ts, detail: item['error'] as String?);
      } else {
        final isNewer = ts.isAfter(existing.lastSeen);
        groups[message] = (
          count: existing.count + 1,
          lastSeen: isNewer ? ts : existing.lastSeen,
          detail: isNewer ? (item['error'] as String?) : existing.detail,
        );
      }
    }

    return (groups.entries.toList()..sort((a, b) => b.value.count.compareTo(a.value.count)))
        .take(10)
        .map((e) => TopError(message: e.key, count: e.value.count, lastSeen: e.value.lastSeen, detail: e.value.detail))
        .toList();
  }
}

class _ExpandedErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void toggle(String message) => state = state == message ? null : message;
}

class _CronJobsNotifier extends AsyncNotifier<List<CronJobSummary>> {
  @override
  Future<List<CronJobSummary>> build() async {
    if (!ref.binding.isClient) return const [];

    final data = await revaliServer.db.list(
      body: const ListBody(
        table: '_cron_jobs',
        limit: 200,
        orderBy: [OrderByTerm(column: 'started', direction: SortDirection.desc)],
      ),
    );

    final seen = <String>{};
    final jobs = <CronJobSummary>[];

    for (final item in _parseItems(data)) {
      final name = item['name'];
      if (name is! String || seen.contains(name)) continue;
      seen.add(name);

      final started = _parseTimestamp(item['started']);
      if (started == null) continue;

      jobs.add(
        CronJobSummary(
          name: name,
          lastStarted: started,
          lastCompleted: _parseTimestamp(item['completed']),
          lastFailed: _parseTimestamp(item['failed']),
          lastError: item['error'] as String?,
        ),
      );
    }

    jobs.sort((a, b) => a.name.compareTo(b.name));
    return jobs;
  }
}

class _TableCountsNotifier extends AsyncNotifier<Map<String, int>> {
  @override
  Future<Map<String, int>> build() async {
    if (!ref.binding.isClient) return const {};

    final tables = ref.watch(sqliteTablesProvider);
    final userTables = [
      for (final t in tables.tables)
        if (!isSystemSqliteTable(t.sqliteName)) t,
    ];
    if (userTables.isEmpty) return const {};

    final counts = <int>[];
    for (final t in userTables) {
      counts.add(await revaliServer.db.count(body: CountBody(table: t.sqliteName)));
    }

    return {for (var i = 0; i < userTables.length; i++) userTables[i].sqliteName: counts[i]};
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

const _requestLogHourMs = 3600000;

/// Start of the 24-hour request window (hour-aligned), shared by stats + graph.
int _requestLogSinceMs() {
  final now = DateTime.now();
  final nowHourMs = now.millisecondsSinceEpoch - (now.millisecondsSinceEpoch % _requestLogHourMs);
  return nowHourMs - 23 * _requestLogHourMs;
}

List<Map<String, Object?>> _parseItems(Map<String, Object?> data) {
  final raw = data['items'];
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is Map) {for (final MapEntry(:key, :value) in e.entries) key.toString(): value as Object?},
  ];
}

DateTime? _parseTimestamp(Object? raw) => switch (raw) {
  final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
  final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
  _ => null,
};
