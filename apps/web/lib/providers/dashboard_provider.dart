import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';

import '../api/dashboard_client.dart';
import '../api/cron_client.dart';
import '../utils/sqlite_table_utils.dart';
import '../utils/user_facing_error.dart';
import 'sqlite_tables_provider.dart';
import 'toast_provider.dart';

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

final excludeAdminProvider = NotifierProvider<_ExcludeAdminNotifier, bool>(_ExcludeAdminNotifier.new);

final dashboardMetricsProvider = AsyncNotifierProvider<_DashboardMetricsNotifier, DashboardMetrics>(
  _DashboardMetricsNotifier.new,
);

final topErrorsProvider = AsyncNotifierProvider<_TopErrorsNotifier, List<TopError>>(_TopErrorsNotifier.new);

// Tracks which error message is currently expanded (null = none).
final expandedErrorProvider = NotifierProvider<_ExpandedErrorNotifier, String?>(_ExpandedErrorNotifier.new);

final cronJobsProvider = AsyncNotifierProvider<_CronJobsNotifier, List<CronJobSummary>>(_CronJobsNotifier.new);

final runningCronJobsProvider = NotifierProvider<RunningCronJobsNotifier, Set<String>>(RunningCronJobsNotifier.new);

final tableCountsProvider = AsyncNotifierProvider<_TableCountsNotifier, Map<String, int>>(_TableCountsNotifier.new);

// ── Implementations ────────────────────────────────────────────────────────────

class _ExcludeAdminNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

class _DashboardMetricsNotifier extends AsyncNotifier<DashboardMetrics> {
  @override
  Future<DashboardMetrics> build() async {
    if (!ref.binding.isClient) {
      return DashboardMetrics(
        stats: const DashboardStats(requestCount24h: 0, errorCount24h: 0, activeSessions: 0, p95ResponseMs: null),
        buckets: const [],
      );
    }

    final excludeAdmin = ref.watch(excludeAdminProvider);
    final since = _requestLogSinceMs();
    final data = await fetchDashboardMetrics(
      server: ref.read(revaliServerProvider),
      since: since,
      excludeAdmin: excludeAdmin,
    );

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

    final excludeAdmin = ref.watch(excludeAdminProvider);
    final since = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;

    final where = excludeAdmin
        ? And([Eq('level', 'error'), Gt('timestamp', since), Eq('is_admin', false)])
        : And([Eq('level', 'error'), Gt('timestamp', since)]);

    final data = await ref.read(revaliServerProvider).db.list(
      body: ListBody(
        table: '_log',
        where: where,
        limit: 500,
        orderBy: [const OrderByTerm(column: 'timestamp', direction: SortDirection.desc)],
      ),
    );

    // Group by a concise error label; items are DESC by timestamp so first occurrence = most recent.
    final groups = <String, ({int count, DateTime lastSeen, String? detail})>{};

    for (final item in _parseItems(data)) {
      final key = _errorGroupKey(item);
      if (key == null) continue;
      final ts = _parseTimestamp(item['timestamp']) ?? DateTime.now();
      final existing = groups[key];
      if (existing == null) {
        groups[key] = (count: 1, lastSeen: ts, detail: item['error'] as String?);
      } else {
        final isNewer = ts.isAfter(existing.lastSeen);
        groups[key] = (
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

    final data = await ref.read(revaliServerProvider).db.list(
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

class RunningCronJobsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  static const _pollInterval = Duration(seconds: 1);
  static const _waitTimeout = Duration(hours: 1);

  Future<void> run(String name) async {
    if (state.contains(name)) return;

    state = {...state, name};
    final startedAfter = DateTime.now();

    try {
      await runCronJob(server: ref.read(revaliServerProvider), name: name);
      await _waitForCompletion(name, startedAfter);
    } catch (error) {
      ref.read(toastProvider.notifier).showError(userFacingError(error));
    } finally {
      ref.invalidate(cronJobsProvider);
      final next = {...state}..remove(name);
      state = next;
    }
  }

  Future<void> _waitForCompletion(String name, DateTime startedAfter) async {
    final deadline = DateTime.now().add(_waitTimeout);

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(_pollInterval);
      ref.invalidate(cronJobsProvider);

      final jobs = await ref.read(cronJobsProvider.future);
      final job = jobs.where((entry) => entry.name == name).firstOrNull;
      if (job == null) continue;
      if (job.lastStarted.isBefore(startedAfter.subtract(const Duration(seconds: 1)))) {
        continue;
      }
      if (job.failed) {
        throw StateError(job.lastError ?? 'Cron job failed');
      }
      if (job.succeeded) {
        ref.read(toastProvider.notifier).showSuccess('Cron job "$name" finished');
        return;
      }
    }

    throw StateError('Timed out waiting for cron job to finish');
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
      counts.add(await ref.read(revaliServerProvider).db.count(body: CountBody(table: t.sqliteName)));
    }

    return {for (var i = 0; i < userTables.length; i++) userTables[i].sqliteName: counts[i]};
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

const _requestLogHourMs = 3600000;
const _errorSummaryMaxLength = 120;

/// Picks a short label for grouping log errors. Falls back to the `error` column
/// for legacy rows logged with the generic "Uncaught error" message.
String? _errorGroupKey(Map<String, Object?> item) {
  final message = item['message'];
  final error = item['error'];

  if (message == 'Uncaught error' && error is String && error.isNotEmpty) {
    return _errorSummaryFromText(error);
  }
  if (message is String && message.isNotEmpty) return _errorSummaryFromText(message);
  if (error is String && error.isNotEmpty) return _errorSummaryFromText(error);
  return null;
}

String _errorSummaryFromText(String text) {
  final line = text.split('\n').first.trim();
  if (line.isEmpty) return text.trim();

  final colon = line.indexOf(':');
  final summary = (colon >= 0 ? line.substring(0, colon) : line).trim();
  final label = summary.isEmpty ? line : summary;

  return label.length <= _errorSummaryMaxLength ? label : '${label.substring(0, _errorSummaryMaxLength - 1)}…';
}

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
