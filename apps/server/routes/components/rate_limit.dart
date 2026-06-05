import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai/src/deps/rate_limiter.dart';
import 'package:revali_router/revali_router.dart';

class RateLimit {
  const RateLimit();

  Future<GuardResult> canContinue(
    dynamic body,
    String ipAddress,
    RateLimitOperation operation,
  ) async {
    // TODO:  get table from AdminAuthBody
    if (body is AdminAuthBody || body is AdminSendResetPasswordAuthBody) {
      return const .pass();
    }

    final table = switch (body) {
      GetBody(:final table) => table,
      ListBody(:final table) => table,
      AuthBody(:final table) => table,
      CreateBody(:final table) => table,
      UpdateOneBody(:final table) => table,
      UpdateBody(:final table) => table,
      DeleteOneBody(:final table) => table,
      DeleteBody(:final table) => table,
      CountBody(:final table) => table,
      StreamCountBody(:final table) => table,
      StreamBody(:final table) => table,
      StreamListBody(:final table) => table,
      SendResetPasswordAuthBody(:final table) => table,
      VerifyEmailAuthBody(:final table) => table,
      _ => throw ArgumentError(
        'Unexpected query body type for rate limit: ${body.runtimeType}',
      ),
    };

    final isAllowed = await rateLimiter.check(
      table: table,
      ipAddress: ipAddress,
      operation: operation,
    );

    return switch (isAllowed) {
      true => const .pass(),
      false => const .block(statusCode: 429, body: 'Rate limit exceeded'),
    };
  }
}
