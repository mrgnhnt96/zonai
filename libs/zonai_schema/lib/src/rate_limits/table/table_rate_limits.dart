part of 'rate_limits.dart';

base class TableRateLimits<S extends Table<R>, R> implements RateLimits<S, R> {
  const TableRateLimits(this.schema);

  @override
  final S schema;

  @override
  rd.TableMeta<S, R> get table => schema.$ as rd.TableMeta<S, R>;

  Future<RateLimitPolicy?> getPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> limitPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> countPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> createPolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> updatePolicy() async => .defaultPolicy;

  Future<RateLimitPolicy?> deletePolicy() async => .defaultPolicy;

  /// Policy for one custom operation (`TableOperations.custom`).
  ///
  /// [operation] is the operation name when the host could validate it against
  /// the table's registered `TableRules`/`RowRules.customOperations`, and each
  /// such name gets its own rate-limit counter.
  ///
  /// It is `null` when the host could not validate the caller-supplied name
  /// cheaply — rules running in a worker rather than in-process. An
  /// unvalidated name must never become a bucket dimension (a caller could
  /// rotate it to land on a fresh counter every request), so the host falls
  /// back to one coarse per-table counter shared by every custom operation and
  /// asks for its policy with `null`. Returning a policy here still limits
  /// those requests; returning `null` leaves them unlimited.
  Future<RateLimitPolicy?> customPolicy(String? operation) async =>
      .defaultPolicy;
}
