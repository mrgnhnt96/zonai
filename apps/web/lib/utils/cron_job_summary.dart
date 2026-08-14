final class CronJobSummary {
  const CronJobSummary({required this.name, this.lastStarted, this.lastCompleted, this.lastFailed, this.lastError});

  final String name;
  final DateTime? lastStarted;
  final DateTime? lastCompleted;
  final DateTime? lastFailed;
  final String? lastError;

  bool get hasRun => lastStarted != null;
  bool get succeeded => lastCompleted != null && lastFailed == null;
  bool get failed => lastFailed != null;
  bool get inProgress => lastStarted != null && lastCompleted == null && lastFailed == null;

  Duration? get duration {
    if (lastCompleted == null || lastStarted == null) return null;
    return lastCompleted!.difference(lastStarted!);
  }
}

List<CronJobSummary> mergeCronJobSummaries(List<String> names, Map<String, CronJobSummary> historyByName) {
  final jobs = [for (final name in names) historyByName[name] ?? CronJobSummary(name: name)];
  jobs.sort((a, b) => a.name.compareTo(b.name));
  return jobs;
}

DateTime? parseCronTimestamp(Object? raw) => switch (raw) {
  final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
  final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
  _ => null,
};

Map<String, CronJobSummary> cronHistoryFromListItems(List<Map<String, Object?>> items) {
  final history = <String, CronJobSummary>{};
  for (final item in items) {
    final name = item['name'];
    if (name is! String || history.containsKey(name)) continue;

    final started = parseCronTimestamp(item['started']);
    if (started == null) continue;

    history[name] = CronJobSummary(
      name: name,
      lastStarted: started,
      lastCompleted: parseCronTimestamp(item['completed']),
      lastFailed: parseCronTimestamp(item['failed']),
      lastError: item['error'] as String?,
    );
  }
  return history;
}
