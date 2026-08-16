import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai/src/deps/rate_limiter.dart';
import 'package:revali_router/revali_router.dart';

class RateLimit {
  const RateLimit();

  /// Synthetic bucket key for admin auth flows, which carry no collection of
  /// their own. Reserved: real collection names cannot begin with `__`.
  static const String _adminAuthBucket = '__admin_auth__';

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
