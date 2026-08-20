import 'package:jaspr_test/jaspr_test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/auth/auth_routes.dart';
import 'package:zonai_web/components/app_shell_gate.dart';
import 'package:zonai_web/utils/page_title.dart';

/// The auth pages that stay reachable when the browser already holds a
/// dashboard session.
///
/// The bug these pin: a password-reset email opened in a signed-in browser
/// landed on `/_`. SSR mounted `HomeAppShell` because the cookie verified,
/// `HomeRouter` bounces every [AuthRoutes.isSignInPath] location home, and the
/// reset callback is in that set — so the link was swallowed with no sign it
/// had ever been followed. The token in it names an account by email and need
/// not be the one signed in, so a session is not a reason to refuse it.
///
/// Verify-email had the same shape with an extra twist: `AuthNotifier` carved
/// it out, `HomeRouter` wrote the same carve-out as `isSignInPath(path) ||
/// isVerifyEmailCallbackPath(path)` — a disjunction with a subset, so it never
/// excluded anything — and `homeRoutes` had nothing to render for it anyway.

/// Every form the same route arrives in: bare, mounted, and carrying its
/// secret.
List<String> _forms(String path) {
  return [path, '/_$path', '$path?s=abc', '/_$path?s=abc'];
}

void main() {
  group('the reachable set', () {
    test('holds the reset-password and verify-email callbacks', () {
      for (final path in [..._forms(AuthRoutes.resetPasswordCallback), ..._forms(AuthRoutes.verifyEmailCallback)]) {
        expect(AuthRoutes.isSignedInReachableAuthPath(path), isTrue, reason: path);
      }
    });

    test('holds nothing else', () {
      for (final path in [
        AuthRoutes.home,
        AuthRoutes.signIn,
        AuthRoutes.forType(AuthType.password),
        AuthRoutes.forType(AuthType.oauth),
        // Asks for a link by email; a signed-in visitor has the account open.
        // Note it is a *prefix-sibling* of the callback, so a `startsWith`
        // implementation would wrongly sweep it in.
        ..._forms(AuthRoutes.resetPasswordRequest),
        // Arriving here with a session is the success path: the server minted
        // the cookie on its own 302, so home is where this visitor was going.
        ..._forms(AuthRoutes.oauthCallback),
        // Would mint a second, different session over the first.
        ..._forms(AuthRoutes.magicLinkCallback),
        // Spent on this browser — whoever is at the keyboard is already an
        // admin.
        ..._forms(AuthRoutes.adminInviteAccept),
        AuthRoutes.tables,
        AuthRoutes.admins,
      ]) {
        expect(AuthRoutes.isSignedInReachableAuthPath(path), isFalse, reason: path);
      }
    });

    test('is a strict subset of the paths a session is bounced away from', () {
      // The carve-out only does work because every member is also an
      // `isSignInPath`. If one ever left that set the exception would go
      // quiet — still passing, still excluding a path nobody bounces.
      for (final path in [AuthRoutes.resetPasswordCallback, AuthRoutes.verifyEmailCallback]) {
        expect(AuthRoutes.isSignInPath(path), isTrue, reason: path);
      }
    });
  });

  group('the shell gate', () {
    test('hands a signed-in reset link to the auth shell, not the dashboard', () {
      for (final path in _forms(AuthRoutes.resetPasswordCallback)) {
        expect(AppShellGate.showsHomeShell(initialSignedIn: true, initialPath: path), isFalse, reason: path);
      }
    });

    test('hands a signed-in verify-email link to the auth shell', () {
      for (final path in _forms(AuthRoutes.verifyEmailCallback)) {
        expect(AppShellGate.showsHomeShell(initialSignedIn: true, initialPath: path), isFalse, reason: path);
      }
    });

    test('still gives a session the dashboard everywhere else', () {
      for (final path in [
        AuthRoutes.home,
        AuthRoutes.tables,
        AuthRoutes.forTable('authors'),
        AuthRoutes.admins,
        AuthRoutes.maintenance,
        AuthRoutes.signIn,
        AuthRoutes.oauthCallback,
        AuthRoutes.magicLinkCallback,
        AuthRoutes.adminInviteAccept,
        AuthRoutes.resetPasswordRequest,
      ]) {
        expect(AppShellGate.showsHomeShell(initialSignedIn: true, initialPath: path), isTrue, reason: path);
      }
    });

    test('gives the auth shell to every path when there is no session', () {
      for (final path in [AuthRoutes.home, AuthRoutes.tables, AuthRoutes.resetPasswordCallback]) {
        expect(AppShellGate.showsHomeShell(initialSignedIn: false, initialPath: path), isFalse, reason: path);
      }
    });
  });

  group('the page title', () {
    // Decided above the `signedIn` gate, because the page is reachable in both
    // states and a title that changed with the cookie would announce the
    // dashboard on a reset page.
    test('names the reset page in either session state', () {
      for (final signedIn in [true, false]) {
        expect(
          PageTitle.resolve(appName: 'Zonai', signedIn: signedIn, path: AuthRoutes.resetPasswordCallback),
          'Zonai — Reset password',
          reason: 'signedIn: $signedIn',
        );
        expect(
          PageTitle.description(appName: 'Zonai', signedIn: signedIn, path: AuthRoutes.resetPasswordCallback),
          'Choose a new password for your Zonai account.',
          reason: 'signedIn: $signedIn',
        );
      }
    });

    test('names the verify page in either session state', () {
      for (final signedIn in [true, false]) {
        expect(
          PageTitle.resolve(appName: 'Zonai', signedIn: signedIn, path: AuthRoutes.verifyEmailCallback),
          'Zonai — Verify email',
          reason: 'signedIn: $signedIn',
        );
      }
    });

    test('carries no secret out of the URL', () {
      // `resolve` normalizes before matching, so the `?s=` never reaches the
      // tab, the history entry, or a screenshot of either.
      final title = PageTitle.resolve(
        appName: 'Zonai',
        signedIn: true,
        path: '${AuthRoutes.resetPasswordCallback}?s=c2VjcmV0OmFAYi5jb20=',
      );
      expect(title, 'Zonai — Reset password');
      expect(title, isNot(contains('s=')));
    });
  });
}
