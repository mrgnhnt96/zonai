import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'rate_limit.dart';

/// Rate limits for handlers that pass the table via `@Query()`.
///
/// Annotate with `@QueryRateLimit<GetBody>(RateLimitOperation.get)` etc.
final class QueryRateLimit<T> extends RateLimit implements LifecycleComponent {
  const QueryRateLimit(this.operation);

  final RateLimitOperation operation;

  Future<GuardResult> check(@Query() T body, @Ip() String ipAddress) async {
    return await canContinue(body, ipAddress, operation);
  }
}
