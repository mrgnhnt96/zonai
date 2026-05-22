part of 'rate_limits.dart';

base class CollectionRateLimits<S extends Collection<R>, R>
    implements RateLimits<S, R> {
  const CollectionRateLimits(this.schema);

  @override
  final S schema;

  @override
  Table<S, R> get table => Table.getFor(schema);

  Future<RateLimitPolicy?> getPolicy() async => RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> limitPolicy() async => RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> countPolicy() async => RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> createPolicy() async => RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> updatePolicy() async => RateLimitPolicy.defaultPolicy;

  Future<RateLimitPolicy?> deletePolicy() async => RateLimitPolicy.defaultPolicy;
}
