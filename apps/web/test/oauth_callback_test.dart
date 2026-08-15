import 'package:jaspr_test/jaspr_test.dart';
import 'package:zonai_web/auth/auth_routes.dart';
import 'package:zonai_web/components/oauth_callback_screen.dart';
import 'package:zonai_web/server/session_auth.dart';
import 'package:zonai_web/utils/zonai_cookie.dart';

void main() {
  group('OAuthCallbackScreen', () {
    testComponents(
      'explains a user-cancelled sign-in instead of failing',
      url: '/_/auth/oauth/callback?error=access_denied',
      (tester) async {
        tester.pumpComponent(const OAuthCallbackScreen());
        await tester.pump();

        expect(
          find.text(
            'Sign-in was cancelled. Nothing happened to your account — '
            'you can try again or pick another method.',
          ),
          findsOneComponent,
        );
        expect(find.text('Back to sign in'), findsOneComponent);
      },
    );

    testComponents(
      'does not reflect the provider-supplied error_description',
      url:
          '/_/auth/oauth/callback?error=access_denied'
          '&error_description=Totally%20trustworthy%20text%20from%20the%20provider',
      (tester) async {
        tester.pumpComponent(const OAuthCallbackScreen());
        await tester.pump();

        expect(find.text('Totally trustworthy text from the provider'), findsNothing);
      },
    );

    testComponents(
      'falls back to generic copy for an unknown error code',
      url: '/_/auth/oauth/callback?error=invalid_client',
      (tester) async {
        tester.pumpComponent(const OAuthCallbackScreen());
        await tester.pump();

        expect(
          find.text('The provider could not sign you in. Try again, or pick another sign-in method.'),
          findsOneComponent,
        );
      },
    );

    testComponents(
      'reports an incomplete sign-in when no error and no session arrived',
      url: '/_/auth/oauth/callback',
      (tester) async {
        tester.pumpComponent(const OAuthCallbackScreen());
        await tester.pump();

        expect(find.text('Sign-in did not complete. Try again, or pick another sign-in method.'), findsOneComponent);
      },
    );
  });

  group('oauthCallbackErrorMessage', () {
    test('maps every provider spelling of "the user pressed cancel"', () {
      const cancelled =
          'Sign-in was cancelled. Nothing happened to your account — you can try again or pick another method.';
      expect(oauthCallbackErrorMessage('access_denied'), cancelled);
      expect(oauthCallbackErrorMessage('user_cancelled_authorize'), cancelled);
      expect(oauthCallbackErrorMessage('user_cancelled_login'), cancelled);
    });

    test('separates a provider outage from a rejection', () {
      expect(oauthCallbackErrorMessage('temporarily_unavailable'), contains('Try again in a moment'));
      expect(oauthCallbackErrorMessage('server_error'), contains('Try again in a moment'));
    });
  });

  // A successful callback never reaches [OAuthCallbackScreen]: the server's
  // 302 writes `zonai_auth_token` before the browser gets here, so SSR
  // resolves a session, `AppShellGate` mounts [HomeAppShell], and `HomeRouter`
  // forwards the path to the dashboard. The two moving parts are asserted
  // separately below rather than by pumping the shell — mounting
  // [HomeAppShell] mounts a `Router`, and jaspr_router's server history
  // manager throws "Routing unavailable on the server" under `testComponents`.
  group('the successful callback lands on the signed-in shell', () {
    test('SSR mounts the signed-in shell for a request carrying the session', () {
      // Same cookie both ways: `AuthController._redirect` writes
      // `ZonaiCookie.authToken` — this app's own enum, which the server
      // package imports — so there is no second cookie name to drift.
      expect(ZonaiCookie.authToken.key, 'zonai_auth_token');
      expect(
        ssrShowsSignedInShell(const SsrSession(signedIn: true, clearAuthCookie: false), 'jwt-minted-by-oauth'),
        isTrue,
      );
    });

    test('HomeRouter then forwards the callback path to the dashboard', () {
      // `HomeRouter._redirect` sends every `isSignInPath` location home; the
      // callback path has to be one of them or a freshly signed-in user is
      // stranded on a route the home shell does not serve.
      expect(AuthRoutes.isSignInPath(AuthRoutes.oauthCallback), isTrue);
      expect(AuthRoutes.isSignInPath('/_/auth/oauth/callback'), isTrue);
    });
  });
}
