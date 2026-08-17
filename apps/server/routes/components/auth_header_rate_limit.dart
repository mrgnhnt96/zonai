import 'dart:io' show HttpHeaders;

import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'rate_limit.dart';

/// Rate limits auth handlers that identify the collection from the Bearer token.
final class AuthHeaderRateLimit extends RateLimit
    implements LifecycleComponent {
  const AuthHeaderRateLimit(this.operation);

  final RateLimitOperation operation;

  /// Synthetic bucket key for token-identified auth flows. We deliberately do
  /// NOT bucket on the token's `table` claim: `Jwt.parse` decodes without
  /// verifying the signature, so a caller could forge/rotate `table` to land
  /// every request in a fresh counter and dodge the limit entirely. A single
  /// per-IP bucket cannot be rotated. Reserved: real collection names cannot
  /// begin with `__`.
  static const String _authHeaderBucket = '__auth_header__';

  Future<GuardResult> check(
    @Header(HttpHeaders.authorizationHeader) String authorization,
    @Ip() String ipAddress,
  ) async {
    final token = _parseBearerToken(authorization);
    if (token == null) {
      // Missing/invalid token — let the route handler return 401.
      return const GuardResult.pass();
    }

    // Bucket per IP, not per (unverified) token claim.
    return checkByTable(_authHeaderBucket, ipAddress, operation);
  }

  static String? _parseBearerToken(String authorization) {
    final trimmed = authorization.trim();
    const prefix = 'Bearer ';
    if (trimmed.length >= prefix.length &&
        trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      return trimmed.substring(prefix.length).trim();
    }
    return null;
  }
}
