import 'dart:io' show HttpHeaders;

import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'rate_limit.dart';

// ! MUST keep `implements LifecycleComponent`. Revali's server generator
// decides an annotation contributes a guard by matching its static type
// against that marker -- drop the clause and the annotation compiles,
// generates, tests green, and silently guards nothing. That is
// known-issues.md #1; `admin_invite_rate_limit_test.dart` pins it.

/// Rate limits `POST /admin/invites` under [RateLimitOperation.adminInvite],
/// bucketed by the auth table named in the caller's Bearer token.
///
/// Not [AuthHeaderRateLimit], which is otherwise exactly this: that one
/// declares its header parameter non-nullable, and this route must answer a
/// *missing* header with the handler's 403 rather than whatever revali does
/// with an unsatisfiable parameter. A guard that cannot run is a worse answer
/// than a guard that passes an unauthenticated request straight into a route
/// that refuses it.
///
/// Bucketing by the token's table rather than by the invited address is
/// deliberate. The address is caller-supplied and unbounded, so bucketing on
/// it would hand every new address a fresh counter — the identical bypass
/// [RateLimit.checkCustomOperation] exists to close for `:operation`, and the
/// per-address limit `_inviteAdmin` already enforces is exactly the one that
/// does *not* bound walking an address list.
final class AdminInviteRateLimit extends RateLimit
    implements LifecycleComponent {
  const AdminInviteRateLimit();

  Future<GuardResult> check(
    @Header(HttpHeaders.authorizationHeader) String? authorization,
    @Ip() String ipAddress,
  ) async {
    final token = _parseBearerToken(authorization);
    final jwt = token == null ? null : Jwt.parse(token);
    if (jwt == null) {
      // Nothing to bucket by. The route handler refuses it with a 403; a
      // guard that invented a bucket here would only be limiting requests
      // that are already being rejected.
      return const GuardResult.pass();
    }

    return checkByTable(jwt.table, ipAddress, RateLimitOperation.adminInvite);
  }

  static String? _parseBearerToken(String? authorization) {
    if (authorization == null) return null;

    final trimmed = authorization.trim();
    const prefix = 'Bearer ';
    if (trimmed.length >= prefix.length &&
        trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      final token = trimmed.substring(prefix.length).trim();
      return token.isEmpty ? null : token;
    }
    return null;
  }
}
