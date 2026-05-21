import 'dart:async';

import 'package:jaspr_riverpod/jaspr_riverpod.dart';
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

  @override
  bool build() {
    final binding = ref.binding;
    if (!binding.isClient) {
      return initialSignedIn;
    }

    ref.listen(authRouteProvider, _onAuthRouteChanged);
    scheduleMicrotask(_syncRouteForAuthState);
    return _hasAuthToken();
  }

  void _onAuthRouteChanged(String? previous, String next) {
    if (!state) return;

    if (!AuthRoutes.isSignInPath(next)) return;

    // Back from the app to a sign-in URL should leave the session.
    if (previous != null && !AuthRoutes.isSignInPath(previous)) {
      signOut();
      return;
    }

    // Signed in but URL is still a sign-in path (bookmark, refresh, etc.).
    ref.read(authRouteProvider.notifier).navigateTo(AuthRoutes.home, replace: true);
  }

  Future<void> sendOtp({required String email}) async {
    try {
      await revaliServer.auth.authenticate(body: AdminSendOtpAuthBody(email: email));
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> verifyOtp({required String email, required String code}) async {
    try {
      final response = await revaliServer.auth.confirm(
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
      await revaliServer.auth.authenticate(body: AdminSendMagicLinkAuthBody(email: email));
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> verifyMagicLink({required String secret}) async {
    try {
      final response = await revaliServer.auth.confirm(body: AdminVerifyMagicLinkAuthBody(secret: secret));

      signIn(response!['accessToken'] as String);
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> sendResetPassword({required String email}) async {
    try {
      await revaliServer.auth.sendResetPassword(body: AdminSendResetPasswordAuthBody(email: email));
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> confirmResetPassword({required String token, required String newPassword}) async {
    try {
      await revaliServer.auth.confirm(
        body: ConfirmResetPasswordAuthBody(token: token, newPassword: newPassword),
      );
      await _clearSession(notifyRoute: false);
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> signInWithPassword({required String email, required String password}) async {
    try {
      final session = await revaliServer.auth.adminAuthenticate(
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
    state = true;
    _syncRouteForAuthStateWithSignedIn(true);
  }

  Future<void> signOut() async {
    await _clearSession();
  }

  Future<void> _clearSession({bool notifyRoute = true}) async {
    final token = ZonaiCookie.authToken.read();
    if (token != null) {
      try {
        await revaliServer.auth.logout(authorization: 'Bearer $token');
      } catch (_) {}
    }
    ZonaiCookie.authToken.remove();
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

    final route = ref.read(authRouteProvider.notifier);
    if (signedIn) {
      final path = ref.read(authRouteProvider);
      if (AuthRoutes.isSignInPath(path)) {
        route.navigateTo(AuthRoutes.home, replace: true);
      }
      return;
    }

    final path = ref.read(authRouteProvider);
    if (!AuthRoutes.isSignInPath(path)) {
      route.navigateTo(AuthRoutes.signIn, replace: true);
    }
  }

  static bool _hasAuthToken() {
    final token = ZonaiCookie.authToken.read();
    return token != null && token.isNotEmpty;
  }
}
