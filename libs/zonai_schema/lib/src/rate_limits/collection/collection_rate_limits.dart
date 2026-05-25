part of 'rate_limits.dart';

base class CollectionRateLimits<S extends Collection<R>, R>
    implements RateLimits<S, R> {
  const CollectionRateLimits(this.schema);

  @override
  final S schema;

  @override
  Table<S, R> get table => Table.getFor(schema);

  Future<RateLimitPolicy?> getPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> limitPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> countPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> createPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> updatePolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> deletePolicy() async => .defaultPolicy;
}
