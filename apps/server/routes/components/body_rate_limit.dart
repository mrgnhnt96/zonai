import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'rate_limit.dart';

/// Rate limits for handlers that pass the table via `@Body()`.
///
/// Annotate with `@BodyRateLimit<CreateBody>(RateLimitOperation.create)` etc.
final class BodyRateLimit<T> extends RateLimit implements LifecycleComponent {
  const BodyRateLimit(this.operation);

  final RateLimitOperation operation;

  Future<GuardResult> check(@Body() T body, @Ip() String ipAddress) async {
    return await canContinue(body, ipAddress, operation);
  }
}
