import 'dart:async';

import 'package:zonai_web/gen/client/client.dart';
import 'package:revali_client/revali_client.dart';
import 'package:zonai_web/utils/zonai_cookie.dart';

const revaliBaseUrl = String.fromEnvironment('REVALI_BASE_URL', defaultValue: 'http://localhost:8080');

typedef UnauthorizedHandler = void Function();

UnauthorizedHandler? _unauthorizedHandler;

/// Called by [AuthNotifier] on the client so API 403 responses sign the user out.
void registerUnauthorizedHandler(UnauthorizedHandler? handler) {
  _unauthorizedHandler = handler;
}

/// Shared Revali client for the web app.
final revaliServer = Server(
  baseUrl: Uri.parse(revaliBaseUrl),
  client: HttpPackageClient(interceptors: [_AuthorizationInterceptor(), _UnauthorizedInterceptor()]),
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

final class _UnauthorizedInterceptor implements HttpInterceptor {
  @override
  void onRequest(HttpRequest request) {}

  @override
  void onResponse(HttpResponse response) {
    if (response.statusCode == 403) {
      _unauthorizedHandler?.call();
    }
  }
}
