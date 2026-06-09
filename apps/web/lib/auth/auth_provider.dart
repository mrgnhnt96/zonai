import 'dart:async';

import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';
import 'package:zonai_web/auth/auth_route_provider.dart';
import 'package:zonai_web/auth/auth_routes.dart';
import 'package:zonai_web/utils/zonai_cookie.dart';

final authProvider = NotifierProvider<AuthNotifier, bool>(AuthNotifier.new);

class AuthNotifier extends Notifier<bool> {
  AuthNotifier({this.initialSignedIn = false});

  /// Seed from the incoming request cookie during SSR (see [AppShell] override).
  final bool initialSignedIn;

  get _revaliServer => ref.read(revaliServerProvider);

  @override
  bool build() {
    final binding = ref.binding;
    if (!binding.isClient) {
      return initialSignedIn;
    }

    registerUnauthorizedHandler(_onUnauthorizedResponse);
    ref.onDispose(() => registerUnauthorizedHandler(null));

    ref.listen(authRouteProvider, _onAuthRouteChanged);
    scheduleMicrotask(_syncRouteForAuthState);
    return _hasAuthToken();
  }

  void _onUnauthorizedResponse() {
    if (!state) return;
    unawaited(signOut(callServer: false));
  }

  void _onAuthRouteChanged(String? previous, String next) {
    if (!state) return;

    if (AuthRoutes.isVerifyEmailCallbackPath(next)) return;

    if (!AuthRoutes.isSignInPath(next)) return;

    // Back from the app to a sign-in URL should leave the session.
    if (previous != null && !AuthRoutes.isSignInPath(previous)) {
      signOut();
      return;
    }

    // Signed in but URL is still a sign-in path (bookmark, refresh, etc.).
    web.window.location.assign(AuthRoutes.toUrlPath(AuthRoutes.home));
  }

  Future<void> sendOtp({required String email}) async {
    try {
      await _revaliServer.auth.authenticate(body: AdminSendOtpAuthBody(email: email));
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> verifyOtp({required String email, required String code}) async {
    try {
      final response = await _revaliServer.auth.confirm(
        body: AdminVerifyOtpAuthBody(email: email, code: code),
      );

      signIn(response!['accessToken'] as String);
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> sendMagicLink({required String email}) async {
    try {
      await _revaliServer.auth.authenticate(body: AdminSendMagicLinkAuthBody(email: email));
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> verifyMagicLink({required String secret}) async {
    try {
      final response = await _revaliServer.auth.confirm(body: AdminVerifyMagicLinkAuthBody(secret: secret));

      signIn(response!['accessToken'] as String);
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> sendResetPassword({required String email}) async {
    try {
      await _revaliServer.auth.sendResetPassword(body: AdminSendResetPasswordAuthBody(email: email));
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> confirmResetPassword({required String token, required String newPassword}) async {
    try {
      await _revaliServer.auth.confirm(
        body: ConfirmResetPasswordAuthBody(token: token, newPassword: newPassword),
      );
      await _clearSession(notifyRoute: false);
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> verifyEmail({required String token}) async {
    try {
      await _revaliServer.auth.confirm(body: ConfirmVerifyEmailAuthBody(token: token));
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> sendVerifyEmail() async {
    final token = ZonaiCookie.authToken.read();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in to send a verification email');
    }

    try {
      await _revaliServer.auth.sendVerifyEmail(authorization: 'Bearer $token');
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> signInWithPassword({required String email, required String password}) async {
    try {
      final session = await _revaliServer.auth.adminAuthenticate(
        body: AdminSignInAuthBody(email: email, password: password),
      );

      final accessToken = session!['accessToken'];
      if (accessToken is! String || accessToken.isEmpty) {
        throw StateError('Sign-in succeeded but no access token was returned');
      }

      signIn(accessToken);
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  void signIn(String accessToken) {
    ZonaiCookie.authToken.write(accessToken);
    if (ref.binding.isClient) {
      web.window.location.assign(AuthRoutes.toUrlPath(AuthRoutes.home));
      return;
    }
    state = true;
    _syncRouteForAuthStateWithSignedIn(true);
  }

  Future<void> refreshSession() async {
    final token = ZonaiCookie.authToken.read();
    if (token == null || token.isEmpty) {
      throw StateError('No session to refresh');
    }

    try {
      final session = await _revaliServer.auth.refreshToken(authorization: 'Bearer $token');

      final accessToken = session?['accessToken'];
      if (accessToken is! String || accessToken.isEmpty) {
        throw StateError('Refresh succeeded but no access token was returned');
      }

      ZonaiCookie.authToken.write(accessToken);
      state = true;
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> signOut({bool callServer = true}) async {
    await _clearSession(callServer: callServer);
  }

  Future<void> _clearSession({bool notifyRoute = true, bool callServer = true}) async {
    if (callServer) {
      final token = ZonaiCookie.authToken.read();
      if (token != null) {
        try {
          await _revaliServer.auth.logout(authorization: 'Bearer $token');
        } catch (_) {}
      }
    }
    ZonaiCookie.authToken.remove();
    if (ref.binding.isClient && notifyRoute) {
      web.window.location.assign(AuthRoutes.toUrlPath(AuthRoutes.signIn));
      return;
    }
    state = false;
    if (notifyRoute) {
      _syncRouteForAuthStateWithSignedIn(false);
    }
  }

  void _syncRouteForAuthState() {
    _syncRouteForAuthStateWithSignedIn(state);
  }

  void _syncRouteForAuthStateWithSignedIn(bool signedIn) {
    if (!ref.binding.isClient) return;

    if (signedIn) {
      final path = ref.read(authRouteProvider);
      if (AuthRoutes.isSignInPath(path) && !AuthRoutes.isVerifyEmailCallbackPath(path)) {
        web.window.location.assign(AuthRoutes.toUrlPath(AuthRoutes.home));
      }
      return;
    }

    final path = ref.read(authRouteProvider);
    if (path == AuthRoutes.home || AuthRoutes.isPublicAuthPath(path)) {
      return;
    }
    web.window.location.assign(AuthRoutes.toUrlPath(AuthRoutes.signIn));
  }

  static bool _hasAuthToken() {
    final token = ZonaiCookie.authToken.read();
    return token != null && token.isNotEmpty;
  }
}
