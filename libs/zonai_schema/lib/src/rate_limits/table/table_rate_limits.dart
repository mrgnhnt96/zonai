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

  /// The policy for the per-IP counter every create is counted against.
  /// Return `null` to drop the per-IP counter, for instance when
  /// [createCounters] limits creates by something other than the caller's
  /// address.
  Future<RateLimitPolicy?> createPolicy() async => .defaultPolicy;

  /// Counters a create is counted against besides [createPolicy]'s per-IP
  /// one, each keyed on a column of the submitted row. See
  /// [RateLimitCounter] for where the key comes from and what happens when a
  /// row has none.
  ///
  /// None by default, so a table that doesn't override this is limited per
  /// IP address only.
  ///
  /// Read once per table for the life of the server, so return the same
  /// counters every time.
  List<RateLimitCounter> createCounters() => const [];

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
