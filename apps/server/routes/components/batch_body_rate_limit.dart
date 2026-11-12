import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'rate_limit.dart';

/// Rate limits `POST /db/batch`: each step counts against its own table and
/// operation, exactly as the same write sent on its own would. A batch is
/// not a way round a table's limits.
///
/// Steps are counted in order and the first that is over its limit refuses
/// the whole batch with its `429`; the steps before it have been counted.
final class BatchBodyRateLimit extends RateLimit implements LifecycleComponent {
  const BatchBodyRateLimit();

  Future<GuardResult> check(
    @Body() BatchBody body,
    @Ip() String ipAddress,
  ) async {
    for (final operation in body.operations) {
      final (stepBody, kind) = switch (operation) {
        BatchCreate(:final body) => (body, RateLimitOperation.create),
        BatchCreateMany(:final body) => (body, RateLimitOperation.create),
        BatchUpdate(:final body) => (body, RateLimitOperation.update),
        BatchUpdateMany(:final body) => (body, RateLimitOperation.update),
        BatchDelete(:final body) => (body, RateLimitOperation.delete),
        BatchDeleteMany(:final body) => (body, RateLimitOperation.delete),
      };
      final result = await canContinue(stepBody, ipAddress, kind);
      if (result.isBlock) return result;
    }
    return const GuardResult.pass();
  }
}
