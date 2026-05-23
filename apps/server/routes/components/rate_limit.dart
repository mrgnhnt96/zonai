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
    // TODO:  get collection from AdminAuthBody
    if (body is AdminAuthBody) {
      return const .pass();
    }

    final collection = switch (body) {
      GetBody(:final collection) => collection,
      ListBody(:final collection) => collection,
      AuthBody(:final collection) => collection,
      CreateBody(:final collection) => collection,
      UpdateOneBody(:final collection) => collection,
      UpdateBody(:final collection) => collection,
      DeleteOneBody(:final collection) => collection,
      DeleteBody(:final collection) => collection,
      StreamBody(:final collection) => collection,
      StreamListBody(:final collection) => collection,
      SendResetPasswordAuthBody(:final collection) => collection,
      VerifyEmailAuthBody(:final collection) => collection,
      _ => throw ArgumentError(
        'Unexpected query body type for rate limit: ${body.runtimeType}',
      ),
    };

    final isAllowed = await rateLimiter.check(
      collection: collection,
      ipAddress: ipAddress,
      operation: operation,
    );

    return switch (isAllowed) {
      true => const .pass(),
      false => const .block(statusCode: 429, body: 'Rate limit exceeded'),
    };
  }
}
