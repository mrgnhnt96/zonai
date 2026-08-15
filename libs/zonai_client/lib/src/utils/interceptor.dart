import 'dart:async';

import 'package:revali_client/revali_client.dart';
import 'package:zonai_client/src/auth.dart';

/// HTTP interceptor that handles the X-Auth token round-trip.
///
/// **Outgoing requests ([onRequest]):** If the request does not already carry an
/// `Authorization` header, the stored access token is read from [Auth] and
/// injected as `Authorization: Bearer <token>`. When no token is stored the
/// header is left unset so public endpoints can be called on the same client.
///
/// **Incoming responses ([onResponse]):** If the response includes an `x-auth`
/// header (lowercase per the `http` package), its value is treated as an updated access token and persisted via
/// [Auth.setToken]. This is how the server delivers tokens after every auth
/// operation (sign-in, sign-up, OTP confirmation, token refresh, etc.) without
/// the client needing to parse response bodies.
class Interceptor implements HttpInterceptor {
  Interceptor({required Auth auth}) : _auth = auth;

  final Auth _auth;

  // The `HttpResponse?` return type is required by revali_client on the git ref
  // CI pins (tool/ci/use_revali_git_overrides.sh); the pub.dev release resolved
  // locally still declares `FutureOr<void>`. The wider type is a valid override
  // of both -- `void` is a top type -- so this file analyzes cleanly either way.
  // Both hooks return `null` throughout: they mutate the request and persist the
  // token, but never substitute a response.
  @override
  FutureOr<HttpResponse?> onRequest(HttpRequest request) async {
    if (request.headers['authorization'] case final authorization?
        when authorization.isNotEmpty) {
      return null;
    }

    final token = await _auth.token;
    if (token == null || token.isEmpty) {
      return null;
    }
    request.headers['authorization'] = 'Bearer $token';
    return null;
  }

  @override
  FutureOr<HttpResponse?> onResponse(HttpResponse response) async {
    final token = response.headers['x-auth'] ?? response.headers['X-Auth'];
    if (token != null && token.isNotEmpty) {
      await _auth.setToken(token);
    }
    return null;
  }
}
