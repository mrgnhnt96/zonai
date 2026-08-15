import 'dart:async';

import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import '../utils/zonai_cookie.dart';
import 'sign_in_screen.dart';
import 'theme/theme_components.dart';

/// Human copy for a provider's RFC 6749 §4.1.2.1 `error` code.
///
/// Only the fixed *code* is ever switched on. The companion
/// `error_description` is provider-controlled free text and is never rendered,
/// matching the server's own stance in `AuthHandler.completeOAuth`.
String oauthCallbackErrorMessage(String error) {
  return switch (error) {
    // `access_denied` is the spec's code; the other two are what Apple and
    // Microsoft send for the same event — the user pressed Cancel.
    'access_denied' || 'user_cancelled_authorize' || 'user_cancelled_login' =>
      'Sign-in was cancelled. Nothing happened to your account — you can try again or pick another method.',
    'temporarily_unavailable' ||
    'server_error' => 'The provider could not complete sign-in right now. Try again in a moment.',
    _ => 'The provider could not sign you in. Try again, or pick another sign-in method.',
  };
}

/// Landing page for the dashboard end of the OAuth redirect flow.
///
/// The session itself is minted **before** the browser gets here: the server's
/// `/auth/oauth/callback/:provider` route writes `zonai_auth_token` on its 302
/// (`AuthController._redirect`), with the same `Path=/; Max-Age=…; SameSite=Lax`
/// and no `HttpOnly` that `CookieStorage.write` uses after a password sign-in.
/// This screen invents no cookie flags of its own — it never writes the cookie
/// at all, it only reacts to whether one arrived.
///
/// So reaching *this* component means SSR did not see a valid session, i.e.
/// something went wrong. A request that does carry a good cookie renders
/// [HomeAppShell] instead, and `HomeRouter` sends it on to the dashboard —
/// [AuthRoutes.isSignInPath] covers [AuthRoutes.oauthCallback] for exactly
/// that reason.
class OAuthCallbackScreen extends StatefulComponent {
  const OAuthCallbackScreen({super.key});

  @override
  State<OAuthCallbackScreen> createState() => OAuthCallbackScreenState();
}

class OAuthCallbackScreenState extends State<OAuthCallbackScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();

    // Decided from the URL, so SSR and hydration reach the same answer for the
    // error case and the markup matches. The cookie check below runs only on
    // the client, and only in the no-error branch.
    final error = Uri.parse(context.url).queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      _error = oauthCallbackErrorMessage(error);
      return;
    }

    scheduleMicrotask(_resolveWithoutError);
  }

  void _resolveWithoutError() {
    if (!context.binding.isClient) return;

    // SSR can decline the shell for a token it could not verify against the
    // `_jwt` table while the worker was restarting. A reload re-runs that
    // check rather than stranding a genuinely signed-in user here.
    final token = ZonaiCookie.authToken.read();
    if (token != null && token.isNotEmpty) {
      web.window.location.assign(AuthRoutes.toUrlPath(AuthRoutes.home));
      return;
    }

    if (!mounted) return;
    setState(() {
      _error = 'Sign-in did not complete. Try again, or pick another sign-in method.';
    });
  }

  void _returnToSignIn() {
    context.goApp(AuthRoutes.signIn);
  }

  @override
  Component build(BuildContext context) {
    return SignInScreen(
      tagline: 'Finishing sign-in',
      child: AuthFormCard(
        children: [
          if (_error case final error?) ...[
            const ZonaiPageTitle('Sign-in'),
            ZonaiErrorText(error),
            AuthActions(
              children: [ZonaiButton(fullWidth: true, onClick: _returnToSignIn, child: .text('Back to sign in'))],
            ),
          ] else ...[
            const ZonaiPageTitle('Signing you in'),
            const ZonaiPageSubtitle('Completing sign-in with your provider…'),
          ],
        ],
      ),
    );
  }
}
