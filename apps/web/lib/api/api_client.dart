import 'dart:async';

import 'package:client/client.dart';
import 'package:revali_client/revali_client.dart';
import 'package:zonai_web/utils/zonai_cookie.dart';

const revaliBaseUrl = String.fromEnvironment('REVALI_BASE_URL', defaultValue: 'http://localhost:8080');

/// Shared Revali client for the web app.
final revaliServer = Server(
  baseUrl: Uri.parse(revaliBaseUrl),
  client: HttpPackageClient(interceptors: [_AuthorizationInterceptor()]),
);

final class _AuthorizationInterceptor implements HttpInterceptor {
  @override
  void onRequest(HttpRequest request) {
    final token = ZonaiCookie.authToken.read();
    if (token != null && token.isNotEmpty) {
      request.headers['authorization'] = 'Bearer $token';
    }
  }

  @override
  FutureOr<void> onResponse(HttpResponse response) {}
}
