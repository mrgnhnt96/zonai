import 'package:test/test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/auth/auth_routes.dart';

void main() {
  group('AuthRoutes mount path', () {
    test('isMountedWebPath', () {
      expect(AuthRoutes.isMountedWebPath('/_'), isTrue);
      expect(AuthRoutes.isMountedWebPath('/_/sign-in'), isTrue);
      expect(AuthRoutes.isMountedWebPath('/'), isFalse);
      expect(AuthRoutes.isMountedWebPath('/sign-in'), isFalse);
    });

    test('toUrlPath maps app routes to mounted URLs', () {
      expect(AuthRoutes.toUrlPath('/'), '/_');
      expect(AuthRoutes.toUrlPath('/sign-in'), '/_/sign-in');
      expect(AuthRoutes.toUrlPath('/tables/foo'), '/_/tables/foo');
    });

    test('toMountedBrowserLocation rewrites router redirects for the address bar', () {
      expect(AuthRoutes.toMountedBrowserLocation('/sign-in'), '/_/sign-in');
      expect(AuthRoutes.toMountedBrowserLocation('/'), '/_');
      expect(AuthRoutes.toMountedBrowserLocation('/_/sign-in'), '/_/sign-in');
      expect(AuthRoutes.toMountedBrowserLocation('/sign-in?next=1'), '/_/sign-in?next=1');
    });

    test('normalizePath strips mount prefix', () {
      expect(AuthRoutes.normalizePath('/_'), '/');
      expect(AuthRoutes.normalizePath('/_/sign-in'), '/sign-in');
      expect(AuthRoutes.normalizePath('/_/tables/foo'), '/tables/foo');
    });

    test('routerRedirectToMountedLocation rewrites legacy mount-less URLs', () {
      expect(AuthRoutes.routerRedirectToMountedLocation('/_/tables/authors'), isNull);
      expect(AuthRoutes.routerRedirectToMountedLocation('/tables/authors'), '/_/tables/authors');
      expect(AuthRoutes.routerRedirectToMountedLocation('/tables/authors?filter=abc'), '/_/tables/authors?filter=abc');
    });
  });

  group('AuthRoutes OAuth paths', () {
    test('the dashboard callback is a public auth path', () {
      expect(AuthRoutes.isOAuthCallbackPath(AuthRoutes.oauthCallback), isTrue);
      expect(AuthRoutes.isOAuthCallbackPath('/_/auth/oauth/callback'), isTrue);
      expect(AuthRoutes.isSignInPath(AuthRoutes.oauthCallback), isTrue);
      expect(AuthRoutes.isPublicAuthPath(AuthRoutes.oauthCallback), isTrue);
    });

    test('the server callback route is a different path, not this one', () {
      // The server owns `/auth/oauth/callback/:provider`; the dashboard's
      // landing page lives under the mount. Neither claims the other's URL.
      expect(AuthRoutes.isOAuthCallbackPath('/auth/oauth/callback/google'), isFalse);
      expect(AuthRoutes.toUrlPath(AuthRoutes.oauthCallback), '/_/auth/oauth/callback');
    });

    test('the oauth sign-in path round-trips through its AuthType', () {
      expect(AuthRoutes.forType(AuthType.oauth), '/sign-in/oauth');
      expect(AuthRoutes.typeFromPath('/sign-in/oauth'), AuthType.oauth);
      expect(AuthRoutes.typeFromPath('/_/sign-in/oauth'), AuthType.oauth);
      expect(AuthRoutes.isSignInPath('/sign-in/oauth'), isTrue);
    });

    test('backPath from the callback offers the picker when there is a choice', () {
      expect(AuthRoutes.backPath(AuthRoutes.oauthCallback, const [AuthType.password, AuthType.oauth]), '/sign-in');
    });

    test('backPath from the callback offers the only method when there is one', () {
      expect(AuthRoutes.backPath(AuthRoutes.oauthCallback, const [AuthType.oauth]), '/sign-in/oauth');
    });

    test('backPath hides the control on an OAuth-only sign-in page', () {
      expect(AuthRoutes.backPath('/sign-in/oauth', const [AuthType.oauth]), isNull);
      expect(AuthRoutes.backPath('/sign-in/oauth', const [AuthType.password, AuthType.oauth]), '/sign-in');
    });

    test('oauthStartUrl appends the mounted callback as redirect_to', () {
      expect(
        AuthRoutes.oauthStartUrl('/auth/oauth/start/google?table=users'),
        '/auth/oauth/start/google?table=users&redirect_to=%2F_%2Fauth%2Foauth%2Fcallback',
      );
    });

    test('oauthStartUrl starts the query string when startPath has none', () {
      expect(
        AuthRoutes.oauthStartUrl('/auth/oauth/start/google'),
        '/auth/oauth/start/google?redirect_to=%2F_%2Fauth%2Foauth%2Fcallback',
      );
    });
  });
}
