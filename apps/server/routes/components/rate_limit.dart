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
      CreateManyBody(:final table) => table,
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
      OAuthBody(:final table) => table,
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

  Future<GuardResult> checkByTable(
    String table,
    String ipAddress,
    RateLimitOperation operation,
  ) async {
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

  /// The one bucket every OAuth callback from one client IP shares.
  ///
  /// A constant, not the `:provider` path segment and not a table, because
  /// `GET|POST /auth/oauth/callback/:provider` carries neither. `state` is
  /// the only thing that identifies the flow and it cannot be resolved to a
  /// table without consuming the challenge, which happens in the db mutator
  /// long after this guard has run. A caller-supplied bucket dimension would
  /// be rotatable — the bypass [checkCustomOperation] exists to close.
  ///
  /// Colliding with a real table of this name is harmless: the unique index
  /// behind the counter is `(clientIp, table, operation)`, and no other
  /// operation is ever recorded under [RateLimitOperation.oauthCallback].
  static const kOAuthCallbackBucket = 'oauth';

  /// Enforces [RateLimitOperation.oauthCallback] under the fixed
  /// [kOAuthCallbackBucket] key. Policy is framework-level and not
  /// overridable per table — see that enum value.
  Future<GuardResult> checkOAuthCallback(String ipAddress) async {
    return await checkByTable(
      kOAuthCallbackBucket,
      ipAddress,
      RateLimitOperation.oauthCallback,
    );
  }

  /// The one bucket every admin OAuth start from one client IP shares.
  ///
  /// `GET /auth/admin/oauth/start/:provider` carries no `table` — resolving
  /// the admin collection server-side is the whole point of the route, so
  /// there is no caller-supplied value to bucket by, exactly as for
  /// [kOAuthCallbackBucket]. Deliberately its *own* constant rather than
  /// reusing the public start route's per-table bucket: sharing one would
  /// let unauthenticated traffic against an app table exhaust the budget for
  /// admin sign-in, which is the one flow that must stay reachable.
  static const kOAuthAdminStartBucket = 'oauth_admin';

  /// Enforces [RateLimitOperation.oauthStart] under the fixed
  /// [kOAuthAdminStartBucket] key.
  Future<GuardResult> checkOAuthAdminStart(String ipAddress) async {
    return await checkByTable(
      kOAuthAdminStartBucket,
      ipAddress,
      RateLimitOperation.oauthStart,
    );
  }

  /// The one bucket every admin-invite OAuth start from one client IP shares.
  ///
  /// `GET /auth/admin/invite/oauth/start/:provider` carries no `table` — the
  /// invite names the collection, server-side — so there is no
  /// caller-supplied value to bucket by, exactly as for
  /// [kOAuthAdminStartBucket]. Not `token`: that is caller-supplied and
  /// rotatable, and bucketing on it would hand a fresh counter to every
  /// guess, which is precisely the enumeration this bounds.
  ///
  /// Its own constant rather than sharing [kOAuthAdminStartBucket]: this
  /// route is reachable by anyone holding an invite link, and admin sign-in
  /// must not be starved by traffic against it.
  static const kOAuthInviteStartBucket = 'oauth_admin_invite';

  /// Enforces [RateLimitOperation.oauthStart] under the fixed
  /// [kOAuthInviteStartBucket] key.
  Future<GuardResult> checkOAuthInviteStart(String ipAddress) async {
    return await checkByTable(
      kOAuthInviteStartBucket,
      ipAddress,
      RateLimitOperation.oauthStart,
    );
  }

  /// Validates [operation] against [table]'s registered custom operations
  /// before it's ever used as a rate-limit bucket dimension — an
  /// unvalidated, caller-supplied name would let a caller rotate it to dodge
  /// the limit entirely (each new name starts at a fresh counter).
  Future<GuardResult> checkCustomOperation(
    String table,
    String operation,
    String ipAddress,
  ) async {
    final registered = rateLimiter.isRegisteredCustomOperation(
      table: table,
      operationName: operation,
    );

    if (registered == false) {
      return const .block(statusCode: 404, body: 'Unknown operation');
    }

    // `registered == null`: can't validate cheaply (e.g. ZONAI_FORCE_WORKERS=1)
    // -- fall back to the coarse per-table `.custom` bucket rather than trust
    // an unvalidated name as a bucket dimension. The rules layer still denies
    // an unregistered operation regardless; this only protects the limiter.
    final isAllowed = await rateLimiter.check(
      table: table,
      ipAddress: ipAddress,
      operation: .custom,
      customOperation: registered == null ? null : operation,
    );

    return switch (isAllowed) {
      true => const .pass(),
      false => const .block(statusCode: 429, body: 'Rate limit exceeded'),
    };
  }
}
