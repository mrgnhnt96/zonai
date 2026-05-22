final class RateLimitPolicy {
  const RateLimitPolicy({required this.maxRequests, required this.window});

  factory RateLimitPolicy.fromJson(Map<String, dynamic> json) {
    return RateLimitPolicy(
      maxRequests: json['maxRequests'] as int,
      window: Duration(seconds: json['window'] as int),
    );
  }

  final int maxRequests;
  final Duration window;

  Map<String, dynamic> toJson() {
    return {'maxRequests': maxRequests, 'window': window.inSeconds};
  }
}
