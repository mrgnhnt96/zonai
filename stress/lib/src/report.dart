import 'stats.dart';

String _fmt(double v) => v.toStringAsFixed(1);

/// Renders a fixed-width text table of [stats], grouped by scenario, with
/// one row per concurrency level.
String renderReport(List<ScenarioStats> stats) {
  final buffer = StringBuffer();
  final byScenario = <String, List<ScenarioStats>>{};
  for (final stat in stats) {
    byScenario.putIfAbsent(stat.scenario, () => []).add(stat);
  }

  const header =
      '| concurrency | req/s   | p50 ms | p90 ms | p95 ms | p99 ms | max ms | errors |';
  const divider =
      '|-------------|---------|--------|--------|--------|--------|--------|--------|';

  for (final entry in byScenario.entries) {
    buffer.writeln();
    buffer.writeln('## ${entry.key}');
    buffer.writeln(header);
    buffer.writeln(divider);
    for (final s
        in entry.value
          ..sort((a, b) => a.concurrency.compareTo(b.concurrency))) {
      final errorLabel = s.errors == 0
          ? '0'
          : '${s.errors} (${(s.errorRate * 100).toStringAsFixed(1)}%)';
      buffer.writeln(
        '| ${s.concurrency.toString().padLeft(11)} '
        '| ${_fmt(s.requestsPerSecond).padLeft(7)} '
        '| ${_fmt(s.p50).padLeft(6)} '
        '| ${_fmt(s.p90).padLeft(6)} '
        '| ${_fmt(s.p95).padLeft(6)} '
        '| ${_fmt(s.p99).padLeft(6)} '
        '| ${_fmt(s.maxMs).padLeft(6)} '
        '| ${errorLabel.padLeft(6)} |',
      );
    }

    final peak = entry.value.reduce(
      (a, b) => a.requestsPerSecond >= b.requestsPerSecond ? a : b,
    );
    buffer.writeln(
      '  peak: ${_fmt(peak.requestsPerSecond)} req/s at concurrency ${peak.concurrency}',
    );
  }

  return buffer.toString();
}
