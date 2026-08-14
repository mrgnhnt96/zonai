import 'dart:async';

import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:revali_client/revali_client.dart';
import 'package:zonai_client/server.dart';
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_web/providers/app_base_url_provider.dart';
import 'package:zonai_web/utils/zonai_cookie_storage.dart';

typedef UnauthorizedHandler = void Function();

UnauthorizedHandler? _unauthorizedHandler;

/// Called by [AuthNotifier] on the client so API 401/403 responses sign the user out.
void registerUnauthorizedHandler(UnauthorizedHandler? handler) {
  _unauthorizedHandler = handler;
}

/// HTTP status codes that mean the stored session is no longer valid.
bool isUnauthorizedStatusCode(int statusCode) => statusCode == 401 || statusCode == 403;

/// Shared Zonai HTTP client for the web app, using [appBaseUrlProvider] from config.
///
/// Token storage uses [ZonaiCookieStorage]; the [Interceptor] X-Auth round-trip
/// keeps the cookie in sync automatically.
final zonaiClientProvider = Provider<ZonaiClient>((ref) {
  final baseUrl = ref.watch(appBaseUrlProvider);
  return ZonaiClient(
    baseUrl: Uri.parse(baseUrl),
    storage: ZonaiCookieStorage(),
    extraInterceptors: [_UnauthorizedInterceptor()],
  );
});

/// The underlying generated [Server], for endpoints without a [ZonaiClient] wrapper.
final revaliServerProvider = Provider<Server>((ref) => ref.watch(zonaiClientProvider).server);

// Returns `FutureOr<HttpResponse?>` rather than `void` because revali_client's
// `HttpInterceptor` declares it that way on the git ref CI pins
// (tool/ci/use_revali_git_overrides.sh), while the pub.dev release resolved
// locally still declares `FutureOr<void>`. The wider return type is a valid
// override of BOTH -- `void` is a top type, so `HttpResponse?` is a subtype of
// it -- which is what lets one source tree analyze cleanly against either.
// `null` means "carry on with what you were given"; neither hook substitutes a
// response, they only observe.
final class _UnauthorizedInterceptor implements HttpInterceptor {
  @override
  FutureOr<HttpResponse?> onRequest(HttpRequest request) => null;

  @override
  FutureOr<HttpResponse?> onResponse(HttpResponse response) {
    if (isUnauthorizedStatusCode(response.statusCode)) {
      _unauthorizedHandler?.call();
    }
    return null;
  }
}
