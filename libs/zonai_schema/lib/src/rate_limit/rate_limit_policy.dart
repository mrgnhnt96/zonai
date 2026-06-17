final class RateLimitPolicy {
  const RateLimitPolicy({required this.maxRequests, required this.window});

  /// Default limit applied when a policy method is not overridden.
  static const defaultPolicy = RateLimitPolicy(
    maxRequests: 100,
    window: Duration(minutes: 1),
  );

  /// Default for `AuthTableRateLimits.externalIdpProvisioningPolicy`.
  /// Tighter than [defaultPolicy] because the first-seen path
  /// provisions a new row in the auth table on each accepted hit.
  static const externalIdpProvisioning = RateLimitPolicy(
    maxRequests: 30,
    window: Duration(hours: 1),
  );

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
