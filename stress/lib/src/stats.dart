/// The outcome of a single request fired by the load generator.
class RequestResult {
  const RequestResult({
    required this.success,
    required this.latency,
    this.statusCode,
    this.error,
  });

  final bool success;
  final Duration latency;
  final int? statusCode;
  final String? error;
}

/// Aggregated timing/throughput numbers for one scenario run at one
/// concurrency level.
class ScenarioStats {
  ScenarioStats({
    required this.scenario,
    required this.concurrency,
    required this.wallTime,
    required List<RequestResult> results,
  }) : total = results.length,
       errors = results.where((r) => !r.success).length,
       _sortedLatenciesMs =
           (results.map((r) => r.latency.inMicroseconds / 1000).toList()
             ..sort());

  final String scenario;
  final int concurrency;
  final Duration wallTime;
  final int total;
  final int errors;
  final List<double> _sortedLatenciesMs;

  int get successes => total - errors;

  double get requestsPerSecond => wallTime.inMicroseconds == 0
      ? 0
      : total / (wallTime.inMicroseconds / 1e6);

  double get errorRate => total == 0 ? 0 : errors / total;

  double _percentile(double p) {
    if (_sortedLatenciesMs.isEmpty) return 0;
    final index = ((_sortedLatenciesMs.length - 1) * p).round();
    return _sortedLatenciesMs[index.clamp(0, _sortedLatenciesMs.length - 1)];
  }

  double get minMs => _sortedLatenciesMs.isEmpty ? 0 : _sortedLatenciesMs.first;
  double get maxMs => _sortedLatenciesMs.isEmpty ? 0 : _sortedLatenciesMs.last;
  double get meanMs => _sortedLatenciesMs.isEmpty
      ? 0
      : _sortedLatenciesMs.reduce((a, b) => a + b) / _sortedLatenciesMs.length;
  double get p50 => _percentile(0.50);
  double get p90 => _percentile(0.90);
  double get p95 => _percentile(0.95);
  double get p99 => _percentile(0.99);

  Map<String, Object?> toJson() => {
    'scenario': scenario,
    'concurrency': concurrency,
    'wallTimeMs': wallTime.inMilliseconds,
    'total': total,
    'errors': errors,
    'requestsPerSecond': requestsPerSecond,
    'errorRate': errorRate,
    'latencyMs': {
      'min': minMs,
      'mean': meanMs,
      'p50': p50,
      'p90': p90,
      'p95': p95,
      'p99': p99,
      'max': maxMs,
    },
  };
}
