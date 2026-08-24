import 'dart:async';

import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_client/zonai_client.dart' show PasswordResetRequiredException;
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/api/api_client.dart';
import 'package:zonai_web/auth/auth_route_provider.dart';
import 'package:zonai_web/auth/auth_routes.dart';
import 'package:zonai_web/utils/reset_password_body.dart';
import 'package:zonai_web/utils/zonai_cookie.dart';

final authProvider = NotifierProvider<AuthNotifier, bool>(AuthNotifier.new);

class AuthNotifier extends Notifier<bool> {
  AuthNotifier({this.initialSignedIn = false});

  /// Seed from the incoming request cookie during SSR (see [AppShell] override).
  final bool initialSignedIn;

  get _client => ref.read(zonaiClientProvider);

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

    if (AuthRoutes.isSignedInReachableAuthPath(next)) return;

    if (!AuthRoutes.isSignInPath(next)) return;

    // Router redirects (not explicit back navigation) should send signed-in users home.
    if (previous != null && !AuthRoutes.isSignInPath(previous)) {
      if (_hasAuthToken()) {
        web.window.location.assign(AuthRoutes.toUrlPath(AuthRoutes.home));
        return;
      }
      signOut();
      return;
    }

    // Signed in but URL is still a sign-in path (bookmark, refresh, etc.).
    web.window.location.assign(AuthRoutes.toUrlPath(AuthRoutes.home));
  }

  Future<void> sendOtp({required String email}) async {
    await _client.auth.admin.sendOtp(body: AdminSendOtpAuthBody(email: email));
  }

  Future<void> verifyOtp({required String email, required String code}) async {
    await _client.auth.confirm(
      body: AdminVerifyOtpAuthBody(email: email, code: code),
    );
    await signIn();
  }

  Future<void> sendMagicLink({required String email}) async {
    await _client.auth.admin.sendMagicLink(body: AdminSendMagicLinkAuthBody(email: email));
  }

  Future<void> verifyMagicLink({required String secret}) async {
    await _client.auth.confirm(body: AdminVerifyMagicLinkAuthBody(secret: secret));
    await signIn();
  }

  /// [table] names the collection the address belongs to, for a reset sent on
  /// someone ELSE's behalf -- a row action in the data browser, where the row
  /// may live in any password collection.
  ///
  /// Omit it only for the dashboard's own door, where the operator is
  /// resetting their OWN admin password and the admin table is resolved
  /// server-side from config. The two are not interchangeable: the admin body
  /// always resolves the admin table, so sending it for a `users` row asks the
  /// server to reset an admin account that does not exist -- and
  /// `_sendResetPassword` returns SILENTLY when there is no auth record
  /// (deliberately, to avoid an existence oracle), so the caller gets a
  /// success it did not earn and the account never hears anything.
  Future<void> sendResetPassword({required String email, String? table}) async {
    await _client.auth.sendResetPassword(
      body: resetPasswordBody(email: email, table: table),
    );
  }

  Future<void> confirmResetPassword({required String token, required String newPassword}) async {
    await _client.auth.confirm(
      body: ConfirmResetPasswordAuthBody(token: token, newPassword: newPassword),
    );
    await _clearSession(notifyRoute: false);
  }

  Future<void> verifyEmail({required String token}) async {
    await _client.auth.confirm(body: ConfirmVerifyEmailAuthBody(token: token));
  }

  Future<void> sendVerifyEmail() async {
    if (!_hasAuthToken()) {
      throw StateError('Sign in to send a verification email');
    }

    await _client.auth.sendVerifyEmail();
  }

  /// Throws [PasswordResetRequiredException] when the account owes a new
  /// password — deliberately let through rather than folded into the generic
  /// failure, because it is the one sign-in refusal that is RECOVERABLE
  /// without leaving this screen. An admin who cannot complete it here has no
  /// dashboard.
  Future<void> signInWithPassword({required String email, required String password}) async {
    await _client.auth.admin.signIn(
      body: AdminSignInAuthBody(email: email, password: password),
    );
    await signIn();
  }

  /// Finishes a forced reset and lands the caller signed in.
  ///
  /// Two calls, and the second is not optional: `POST /auth/confirm` returns
  /// NO session for a password reset. `completePasswordReset` on the client
  /// does both, and [signIn] then does what the ordinary password path does —
  /// writes the cookie and navigates home — so a forced sign-in ends exactly
  /// where an unforced one does.
  ///
  /// Note this is NOT [confirmResetPassword], which is the EMAILED path and
  /// deliberately ends signed OUT: that link reaches whoever owns the account,
  /// on any auth table, and most of them are an app's users rather than
  /// admins. Here the caller is already at the dashboard's own door.
  Future<void> completeForcedPasswordReset({
    required PasswordResetRequiredException refusal,
    required String email,
    required String newPassword,
  }) async {
    await _client.auth.admin.completePasswordReset(refusal: refusal, email: email, newPassword: newPassword);
    await signIn();
  }

  Future<void> signIn() async {
    if (!ref.binding.isClient) {
      state = true;
      _syncRouteForAuthStateWithSignedIn(true);
      return;
    }

    final token = await _client.auth.token;
    if (token == null || token.isEmpty) {
      state = false;
      throw StateError('Sign-in did not return a session token');
    }

    ZonaiCookie.authToken.write(token);
    state = true;
    web.window.location.assign(AuthRoutes.toUrlPath(AuthRoutes.home));
  }

  Future<void> refreshSession() async {
    if (!_hasAuthToken()) {
      throw StateError('No session to refresh');
    }

    await _client.auth.refreshToken();
    state = true;
  }

  Future<void> signOut({bool callServer = true}) async {
    await _clearSession(callServer: callServer);
  }

  Future<void> _clearSession({bool notifyRoute = true, bool callServer = true}) async {
    if (callServer && _hasAuthToken()) {
      try {
        await _client.auth.logout();
      } catch (_) {}
    }
    await _client.auth.clearToken();
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
      if (AuthRoutes.isSignInPath(path) && !AuthRoutes.isSignedInReachableAuthPath(path)) {
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
