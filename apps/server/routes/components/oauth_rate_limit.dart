import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/zonai_schema.dart' show RateLimitOperation;

import 'rate_limit.dart';

// ! Both classes below MUST keep `implements LifecycleComponent`. Revali's
// server generator decides an annotation contributes a guard by matching its
// static type against that marker -- drop the clause and the annotation
// compiles, generates, tests green, and silently guards nothing. That is
// known-issues.md #1; test/lifecycle_component_wiring_test.dart pins it.

/// Rate limits `GET /auth/oauth/start/:provider?table=` under
/// [RateLimitOperation.oauthStart], bucketed by the `table` the caller is
/// starting a flow for.
///
/// Not [QueryRateLimit]: that one reads a whole body object out of a single
/// `?body=` query key (see the generated `__db_route.dart`), whereas the
/// start route takes `table` as its own scalar query parameter.
final class OAuthStartRateLimit extends RateLimit
    implements LifecycleComponent {
  const OAuthStartRateLimit();

  Future<GuardResult> check(
    @Query('table') String table,
    @Ip() String ipAddress,
  ) async {
    return await checkByTable(table, ipAddress, RateLimitOperation.oauthStart);
  }
}

/// Rate limits `GET /auth/admin/oauth/start/:provider` under
/// [RateLimitOperation.oauthStart].
///
/// Not [OAuthStartRateLimit]: that one reads `@Query('table')`, and the admin
/// start route deliberately has no `table` parameter — it resolves the
/// `AsAdmin` collection server-side. See [RateLimit.kOAuthAdminStartBucket]
/// for why this gets its own bucket instead of sharing the public one.
final class OAuthAdminStartRateLimit extends RateLimit
    implements LifecycleComponent {
  const OAuthAdminStartRateLimit();

  Future<GuardResult> check(@Ip() String ipAddress) async {
    return await checkOAuthAdminStart(ipAddress);
  }
}

/// Rate limits `GET /auth/admin/invite/oauth/start/:provider?token=` under
/// [RateLimitOperation.oauthStart].
///
/// Its own bucket rather than [OAuthAdminStartRateLimit]'s, for the reason
/// that one is not [OAuthStartRateLimit]'s: the invite-acceptance route is
/// reachable by anyone holding an invite link, and sharing a budget with
/// admin sign-in would let traffic against it exhaust the one flow that must
/// stay reachable. See [RateLimit.kOAuthInviteStartBucket].
final class OAuthInviteStartRateLimit extends RateLimit
    implements LifecycleComponent {
  const OAuthInviteStartRateLimit();

  Future<GuardResult> check(@Ip() String ipAddress) async {
    return await checkOAuthInviteStart(ipAddress);
  }
}

/// Rate limits `GET`/`POST /auth/oauth/callback/:provider` under
/// [RateLimitOperation.oauthCallback].
///
/// Takes no table and no provider on purpose — see
/// [RateLimit.kOAuthCallbackBucket] for why a caller-supplied bucket
/// dimension here would be a bypass rather than a refinement.
final class OAuthCallbackRateLimit extends RateLimit
    implements LifecycleComponent {
  const OAuthCallbackRateLimit();

  Future<GuardResult> check(@Ip() String ipAddress) async {
    return await checkOAuthCallback(ipAddress);
  }
}
