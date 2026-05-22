part of 'rate_limits.dart';

base class CollectionRateLimits<S extends Collection<R>, R>
    implements RateLimits<S, R> {
  const CollectionRateLimits(this.schema);

  @override
  final S schema;

  @override
  Table<S, R> get table => Table.getFor(schema);

  Future<RateLimitPolicy?> getPolicy() async => null;

  Future<RateLimitPolicy?> limitPolicy() async => null;

  Future<RateLimitPolicy?> countPolicy() async => null;

  Future<RateLimitPolicy?> createPolicy() async => null;

  Future<RateLimitPolicy?> updatePolicy() async => null;

  Future<RateLimitPolicy?> deletePolicy() async => null;
}
