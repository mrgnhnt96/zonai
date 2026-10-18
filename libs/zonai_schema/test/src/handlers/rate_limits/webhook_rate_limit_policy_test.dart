import 'package:test/test.dart';
import 'package:zonai_schema/src/handlers/rate_limits/db_rate_limits.dart';
import 'package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// `POST /hooks/:name` is limited as a `create` on the reserved
/// `__webhooks__` bucket (apps/server's `WebhookRateLimit`). No table has
/// that name, so the policy must come from the defaults: `RateLimiter.check`
/// treats a `null` policy as unlimited, and the route has no other guard.
void main() {
  test('the webhook bucket resolves the default policy', () async {
    final response = await DbRateLimits(
      rateLimits: [],
    ).dispatch(RateLimitRequest(table: '__webhooks__', operation: .create));

    expect(response.policy, isNotNull, reason: 'null means UNLIMITED');
    expect(response.policy, RateLimitPolicy.defaultPolicy);
  });
}
