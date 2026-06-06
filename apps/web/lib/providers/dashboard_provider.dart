import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

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

  double get errorRate => requestCount24h == 0 ? 0 : errorCount24h / requestCount24h * 100;
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

// ── Providers ─────────────────────────────────────────────────────────────────

final dashboardStatsProvider = AsyncNotifierProvider<_DashboardStatsNotifier, DashboardStats>(
  _DashboardStatsNotifier.new,
);

final requestBucketsProvider = AsyncNotifierProvider<_RequestBucketsNotifier, List<RequestBucket>>(
  _RequestBucketsNotifier.new,
);

final topErrorsProvider = AsyncNotifierProvider<_TopErrorsNotifier, List<TopError>>(_TopErrorsNotifier.new);

// Tracks which error message is currently expanded (null = none).
final expandedErrorProvider = NotifierProvider<_ExpandedErrorNotifier, String?>(_ExpandedErrorNotifier.new);

final cronJobsProvider = AsyncNotifierProvider<_CronJobsNotifier, List<CronJobSummary>>(_CronJobsNotifier.new);

final tableCountsProvider = AsyncNotifierProvider<_TableCountsNotifier, Map<String, int>>(_TableCountsNotifier.new);

// ── Implementations ────────────────────────────────────────────────────────────

class _DashboardStatsNotifier extends AsyncNotifier<DashboardStats> {
  @override
  Future<DashboardStats> build() async {
    if (!ref.binding.isClient) {
      return const DashboardStats(requestCount24h: 0, errorCount24h: 0, activeSessions: 0, p95ResponseMs: null);
    }

    final since = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    // _jwt.expires_at is stored in Unix seconds, not milliseconds
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final (requestData, errorCount, sessionCount) = await (
      revaliServer.db.list(
        body: ListBody(
          table: '_log',
          where: And([Eq('level', 'request'), Gt('timestamp', since)]),
          limit: 5000,
          orderBy: [const OrderByTerm(column: 'timestamp', direction: SortDirection.desc)],
        ),
      ),
      revaliServer.db.count(
        body: CountBody(table: '_log', where: And([Eq('level', 'error'), Gt('timestamp', since)])),
      ),
      revaliServer.db.count(
        body: CountBody(table: '_jwt', where: Gt('expires_at', nowSeconds)),
      ),
    ).wait;

    final requestItems = _parseItems(requestData);

    return DashboardStats(
      requestCount24h: _parseTotal(requestData),
      errorCount24h: errorCount,
      activeSessions: sessionCount,
      p95ResponseMs: _computeP95(requestItems),
    );
  }

  static int? _computeP95(List<Map<String, Object?>> items) {
    final durations = <int>[];
    for (final item in items) {
      final d = _parseDurationMs(item['message']);
      if (d != null) durations.add(d);
    }
    if (durations.isEmpty) return null;
    durations.sort();
    return durations[((durations.length - 1) * 0.95).round()];
  }
}

class _RequestBucketsNotifier extends AsyncNotifier<List<RequestBucket>> {
  @override
  Future<List<RequestBucket>> build() async {
    if (!ref.binding.isClient) return const [];

    final now = DateTime.now();
    const hourMs = Duration(hours: 1);
    final nowHourMs = now.millisecondsSinceEpoch - (now.millisecondsSinceEpoch % hourMs.inMilliseconds);

    // 24 hourly buckets using parallel count() calls — avoids the 500-row list cap.
    final counts = await Future.wait([
      for (var i = 0; i < 24; i++)
        () {
          final start = nowHourMs - (23 - i) * hourMs.inMilliseconds;
          final end = start + hourMs.inMilliseconds;
          return revaliServer.db.count(
            body: CountBody(
              table: '_log',
              where: And([Eq('level', 'request'), Gte('timestamp', start), Lt('timestamp', end)]),
            ),
          );
        }(),
    ]);

    return [
      for (var i = 0; i < 24; i++)
        RequestBucket(
          hour: DateTime.fromMillisecondsSinceEpoch(nowHourMs - (23 - i) * hourMs.inMilliseconds),
          count: counts[i],
        ),
    ];
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

    final counts = await Future.wait([
      for (final t in userTables) revaliServer.db.count(body: CountBody(table: t.sqliteName)),
    ]);

    return {for (var i = 0; i < userTables.length; i++) userTables[i].sqliteName: counts[i]};
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

int _parseTotal(Map<String, Object?> data) => switch (data['total']) {
  final int t => t,
  final num t => t.toInt(),
  _ => 0,
};

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

int? _parseDurationMs(Object? message) {
  if (message is! String) return null;
  final match = RegExp(r'^\[\d+\] (\d+)ms:').firstMatch(message);
  return match != null ? int.tryParse(match.group(1)!) : null;
}
