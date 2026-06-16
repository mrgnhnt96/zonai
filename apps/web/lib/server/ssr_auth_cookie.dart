import 'dart:io';

import 'package:jaspr/server.dart';

import '../utils/zonai_cookie.dart';

/// Clears the auth token cookie on the SSR response.
///
/// [ZonaiCookie.authToken] is not HttpOnly so the browser client can attach it
/// to API requests; match that when expiring the cookie server-side.
void clearAuthCookie(BuildContext context) {
  context.setCookie(
    ZonaiCookie.authToken.key,
    '',
    maxAge: 0,
    path: '/',
    httpOnly: false,
    sameSite: SameSite.lax,
  );
}
