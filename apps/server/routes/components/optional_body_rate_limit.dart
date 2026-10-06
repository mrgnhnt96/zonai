import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'rate_limit.dart';

/// [BodyRateLimit] for a route whose body may be absent.
///
/// `BodyRateLimit<T>` reads `@Body() T`, which revali parses as required: an
/// absent body arrives as `{}`, and the generated guard's only parse arm is
/// `Map data when data.isNotEmpty`, so it throws `MissingArgumentException`
/// (400) before the route runs -- even when the route itself takes `T?`. That
/// made `POST /auth/verify-email` with no body, the "verify my own address"
/// call, unreachable (reported against v0.10.1).
///
/// A present body is limited exactly as [BodyRateLimit] limits it. An absent
/// one names no collection, so it is bucketed per IP on [bucketWithoutBody],
/// the same way `kConfirmBucket` handles a body with no table.
final class OptionalBodyRateLimit<T> extends RateLimit
    implements LifecycleComponent {
  const OptionalBodyRateLimit(this.operation);

  final RateLimitOperation operation;

  /// The per-IP bucket a body-less call to [operation] counts against.
  ///
  /// Reserved like the other synthetic keys: real collection names cannot
  /// begin with `__`, and it holds no `:`, which `RateLimiter.check` splits
  /// custom-operation keys on.
  static String bucketWithoutBody(RateLimitOperation operation) =>
      '__no_body_${operation.name}__';

  Future<GuardResult> check(@Body() T? body, @Ip() String ipAddress) async {
    if (body == null) {
      return await checkByTable(
        bucketWithoutBody(operation),
        ipAddress,
        operation,
      );
    }
    return await canContinue(body, ipAddress, operation);
  }
}
