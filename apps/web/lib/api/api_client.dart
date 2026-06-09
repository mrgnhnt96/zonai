import 'dart:async';

import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_web/gen/client/client.dart';
import 'package:revali_client/revali_client.dart';
import 'package:zonai_web/providers/app_base_url_provider.dart';
import 'package:zonai_web/utils/zonai_cookie.dart';

typedef UnauthorizedHandler = void Function();

UnauthorizedHandler? _unauthorizedHandler;

/// Called by [AuthNotifier] on the client so API 403 responses sign the user out.
void registerUnauthorizedHandler(UnauthorizedHandler? handler) {
  _unauthorizedHandler = handler;
}

Server _createRevaliServer(String baseUrl) => Server(
  baseUrl: Uri.parse(baseUrl),
  client: HttpPackageClient(interceptors: [_AuthorizationInterceptor(), _UnauthorizedInterceptor()]),
);

/// Shared Revali client for the web app, using [appBaseUrlProvider] from config.
final revaliServerProvider = Provider<Server>((ref) {
  final baseUrl = ref.watch(appBaseUrlProvider);
  return _createRevaliServer(baseUrl);
});

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
