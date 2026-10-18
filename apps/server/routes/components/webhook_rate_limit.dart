import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/zonai_schema.dart' show RateLimitOperation;

import 'rate_limit.dart';

// ! MUST keep `implements LifecycleComponent` -- without it the annotation
// compiles and guards nothing. See oauth_rate_limit.dart.

/// Rate limits `POST /hooks/:name` per client IP.
///
/// Not keyed on `:name`: the path is the caller's to pick, so a name-keyed
/// bucket could be rotated around. Counted as [RateLimitOperation.create]
/// under the reserved [kWebhookBucket] -- a delivery is a write -- which keeps
/// the default write policy without adding an operation to the schema.
final class WebhookRateLimit extends RateLimit implements LifecycleComponent {
  const WebhookRateLimit();

  /// Reserved: real collection names cannot begin with `__`.
  static const kWebhookBucket = '__webhooks__';

  Future<GuardResult> check(@Ip() String ipAddress) async {
    return await checkByTable(
      kWebhookBucket,
      ipAddress,
      RateLimitOperation.create,
    );
  }
}
