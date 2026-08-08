import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'rate_limit.dart';

/// Rate limits `PATCH /db/custom/:operation` handlers. Unlike [BodyRateLimit],
/// the operation name comes from the URL, not a fixed [RateLimitOperation] —
/// see [RateLimit.checkCustomOperation] for the validate-before-bucket logic.
final class CustomBodyRateLimit<T extends CustomBody> extends RateLimit
    implements LifecycleComponent {
  const CustomBodyRateLimit();

  Future<GuardResult> check(
    @Param() String operation,
    @Body() T body,
    @Ip() String ipAddress,
  ) async {
    return await checkCustomOperation(body.table, operation, ipAddress);
  }
}
