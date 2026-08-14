class DashboardRequestBucket {
  const DashboardRequestBucket({required this.hour, required this.count});

  final int hour;
  final int count;

  factory DashboardRequestBucket.fromJson(Map<String, dynamic> json) {
    return DashboardRequestBucket(
      hour: json['hour'] as int,
      count: json['count'] as int,
    );
  }

  Map<String, dynamic> toJson() => {'hour': hour, 'count': count};
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.requestCount24h,
    required this.errorCount24h,
    required this.activeSessions,
    required this.requestBuckets,
    this.p95ResponseMs,
  });

  final int requestCount24h;
  final int errorCount24h;
  final int activeSessions;
  final int? p95ResponseMs;
  final List<DashboardRequestBucket> requestBuckets;

  factory DashboardMetrics.fromJson(Map<String, dynamic> json) {
    return DashboardMetrics(
      requestCount24h: json['request_count_24h'] as int,
      errorCount24h: json['error_count_24h'] as int,
      activeSessions: json['active_sessions'] as int,
      p95ResponseMs: json['p95_response_ms'] as int?,
      requestBuckets: [
        for (final bucket in json['request_buckets'] as List)
          DashboardRequestBucket.fromJson(
            Map<String, dynamic>.from(bucket as Map),
          ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'request_count_24h': requestCount24h,
    'error_count_24h': errorCount24h,
    'active_sessions': activeSessions,
    'p95_response_ms': p95ResponseMs,
    'request_buckets': [for (final bucket in requestBuckets) bucket.toJson()],
  };
}
