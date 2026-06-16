import 'dart:io' show HttpHeaders;

import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'rate_limit.dart';

/// Rate limits auth handlers that identify the collection from the Bearer token.
final class AuthHeaderRateLimit extends RateLimit implements LifecycleComponent {
  const AuthHeaderRateLimit(this.operation);

  final RateLimitOperation operation;

  Future<GuardResult> check(
    @Header(HttpHeaders.authorizationHeader) String authorization,
    @Ip() String ipAddress,
  ) async {
    final token = _parseBearerToken(authorization);
    final jwt = token == null ? null : Jwt.parse(token);
    if (jwt == null) {
      // Missing/invalid token — let the route handler return 401.
      return const GuardResult.pass();
    }

    return checkByTable(jwt.table, ipAddress, operation);
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
