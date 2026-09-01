import 'package:clock/clock.dart';
import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai/src/deps/rate_limiter.dart';
import 'package:zonai/src/services/rate_limit_check.dart';
import 'package:revali_router/revali_router.dart';

class RateLimit {
  const RateLimit();

  /// The one place a rate-limit refusal becomes an HTTP response, so every
  /// 429 this guard family emits carries the same headers and body
  /// (GitHub issue #32: a 429 with no `Retry-After` is one a client can only
  /// poll against, and nine agents behind one IP polling is what keeps the
  /// shared bucket empty).
  ///
  /// Header names are lowercase to match revali's own `Throttle` kit. The
  /// seconds are rounded UP and never 0: `Retry-After: 0` tells a client to
  /// retry into the same closed window, and flooring 900ms to 0s would do the
  /// same. `x-ratelimit-reset` is a Unix epoch in whole seconds, UTC, the
  /// GitHub/Laravel convention.
  ///
  /// [check] must be a refusal under a real policy; an unlimited check has no
  /// window to describe and must never reach here.
  static GuardResult exceeded(RateLimitCheck check) {
    assert(!check.allowed, 'exceeded() called with an allowed check');
    final limit = check.limit;
    final resetAt = check.resetAt;
    if (limit == null || resetAt == null) {
      throw ArgumentError.value(
        check,
        'check',
        'an unlimited bucket cannot be exceeded',
      );
    }

    final untilReset = resetAt.difference(clock.now());
    final retryAfter = (untilReset.inMilliseconds / 1000).ceil().clamp(
      1,
      1 << 31,
    );

    return GuardResult.block(
      statusCode: 429,
      headers: {
        'retry-after': '$retryAfter',
        'x-ratelimit-limit': '$limit',
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset':
            '${resetAt.toUtc().millisecondsSinceEpoch ~/ 1000}',
      },
      body: {
        'error': 'Rate limit exceeded',
        'collection': check.table,
        'operation': check.operation.name,
        if (check.customOperation case final custom?) 'customOperation': custom,
        'retryAfter': retryAfter,
      },
    );
  }

  /// `.pass()` or [exceeded], and nothing else -- so the three guard paths
  /// below cannot drift apart in what a 429 looks like.
  static GuardResult _resultFor(RateLimitCheck check) =>
      check.allowed ? const .pass() : exceeded(check);

  /// Synthetic bucket key for admin auth flows, which carry no collection of
  /// their own. Reserved: real collection names cannot begin with `__`.
  static const String _adminAuthBucket = '__admin_auth__';

  /// Synthetic bucket key for `POST /auth/confirm`, which carries no
  /// collection of its own -- [VerifyAuthBody] is a token or a code, not a
  /// table. Reserved: real collection names cannot begin with `__`.
  ///
  /// Per-IP, and deliberately NOT keyed on the address in the payload. The
  /// send side throttles per target address because its harm is a flooded
  /// inbox, which belongs to that address. The harm here is the server's own
  /// CPU, which belongs to nobody in particular -- and an address-keyed
  /// counter on an unauthenticated endpoint answers "is this account real?"
  /// differently for a known address than an unknown one, which is the
  /// enumeration oracle the rest of the auth surface is built to avoid.
  static const String kConfirmBucket = '__auth_confirm__';

  Future<GuardResult> canContinue(
    dynamic body,
    String ipAddress,
    RateLimitOperation operation,
  ) async {
    // Admin auth bodies do not carry a collection (`AdminAuthBody.table`
    // throws), and the admin auth table is resolved server-side from config,
    // so there is no per-collection bucket to use here. Previously these
    // returned `.pass()` unconditionally — admin sign-in / reset were exempt
    // from ALL rate limiting, allowing unlimited online credential guessing
    // against the most privileged accounts. Bucket them on a dedicated,
    // per-IP admin key instead so they are throttled like every other auth
    // flow (a follow-up can additionally bucket on the submitted email).
    if (body is AdminAuthBody || body is AdminSendResetPasswordAuthBody) {
      return checkByTable(_adminAuthBucket, ipAddress, operation);
    }

    // Same shape, same reason. `POST /auth/confirm` was exempt from ALL rate
    // limiting: `RateLimitOperation.confirm` and `confirmPolicy()` are wired
    // in `db_rate_limits.dart`, but the route carried no `@BodyRateLimit`, so
    // nothing ever invoked them -- character for character the defect
    // recorded above for admin auth. Every confirm attempt reaches an Argon2
    // verification (`parts/auth/reset_password.dart`), which is expensive BY
    // DESIGN, so an unauthenticated caller could force unbounded work with a
    // loop of junk tokens. Not a guessing risk: the secret is 32 bytes from
    // `Random.secure()`. It is CPU exhaustion, on the endpoint a forced reset
    // needs most -- the ticket lives 15 minutes.
    if (body is VerifyAuthBody) {
      return checkByTable(kConfirmBucket, ipAddress, operation);
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

    return _resultFor(
      await rateLimiter.check(
        table: table,
        ipAddress: ipAddress,
        operation: operation,
      ),
    );
  }

  Future<GuardResult> checkByTable(
    String table,
    String ipAddress,
    RateLimitOperation operation,
  ) async {
    return _resultFor(
      await rateLimiter.check(
        table: table,
        ipAddress: ipAddress,
        operation: operation,
      ),
    );
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
    return _resultFor(
      await rateLimiter.check(
        table: table,
        ipAddress: ipAddress,
        operation: .custom,
        customOperation: registered == null ? null : operation,
      ),
    );
  }
}
