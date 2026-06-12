import 'dart:async';

import 'package:revali_client/revali_client.dart';
import 'package:zonai_client/src/auth.dart';

/// HTTP interceptor that handles the X-Auth token round-trip.
///
/// **Outgoing requests ([onRequest]):** If the request does not already carry an
/// `Authorization` header, the stored access token is read from [Auth] and
/// injected as `Authorization: Bearer <token>`. Throws [StateError] if no token
/// is available and the header is absent.
///
/// **Incoming responses ([onResponse]):** If the response includes an `X-Auth`
/// header, its value is treated as an updated access token and persisted via
/// [Auth.setToken]. This is how the server delivers tokens after every auth
/// operation (sign-in, sign-up, OTP confirmation, token refresh, etc.) without
/// the client needing to parse response bodies.
class Interceptor implements HttpInterceptor {
  Interceptor({required this._auth});

  final Auth _auth;

  @override
  FutureOr<void> onRequest(HttpRequest request) async {
    final authorization = request.headers['authorization'];
    if (request.headers.containsKey('authorization')) {
      return;
    }

    if (authorization?.length case final length? when length > 0) {
      return;
    }

    final token = await _auth.token;
    if (token == null) {
      throw StateError('No token found');
    }
    request.headers['authorization'] = 'Bearer $token';
  }

  @override
  FutureOr<void> onResponse(HttpResponse response) async {
    if (response.headers['X-Auth'] case final String token) {
      await _auth.setToken(token);
    }
  }
}
