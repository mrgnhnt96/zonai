import 'package:test/test.dart';
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
}
