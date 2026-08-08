part of 'rate_limits.dart';

base class TableRateLimits<S extends Table<R>, R> implements RateLimits<S, R> {
  const TableRateLimits(this.schema);

  @override
  final S schema;

  @override
  rd.TableMeta<S, R> get table => rd.TableMeta.getFor(schema);

  Future<RateLimitPolicy?> getPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> limitPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> countPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> createPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> updatePolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> deletePolicy() async => .defaultPolicy;

  /// Policy for one named custom operation (`TableOperations.custom`).
  /// [operation] is validated against the table's registered
  /// `TableRules`/`RowRules.customOperations` before this is ever called.
  Future<RateLimitPolicy?> customPolicy(String operation) async =>
      .defaultPolicy;
}
