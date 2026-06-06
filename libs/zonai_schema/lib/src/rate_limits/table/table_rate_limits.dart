part of 'rate_limits.dart';

base class TableRateLimits<S extends Table<R>, R> implements RateLimits<S, R> {
  const TableRateLimits(this.schema);

  @override
  final S schema;

  @override
  rd.Table<S, R> get table => rd.Table.getFor(schema);

  Future<RateLimitPolicy?> getPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> limitPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> countPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> createPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> updatePolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> deletePolicy() async => .defaultPolicy;
}
