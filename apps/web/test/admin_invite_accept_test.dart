import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/auth/auth_routes.dart';
import 'package:zonai_web/auth/oauth_providers_provider.dart';
import 'package:zonai_web/auth/supported_auth_types_provider.dart';
import 'package:zonai_web/components/admin_invite_accept_screen.dart';
import 'package:zonai_web/providers/app_name_provider.dart';
import 'package:zonai_web/providers/brand_logo_provider.dart';

/// The invite acceptance screen (`docs/admin-invite-design.md` §3.2, §3.3).
///
/// The requirement these exist for is §3.3's: the screen offers **the methods
/// the admin table declares**, not OAuth by assumption. So the same component
/// is pumped against three different collections and asked what it shows.

OAuthProviderPublic _provider({required String id, required String displayName, required OAuthProviderKind kind}) {
  return OAuthProviderPublic(
    id: id,
    displayName: displayName,
    table: 'staff',
    kind: kind,
    startPath: '/auth/oauth/start/$id?table=staff',
  );
}

Component _scoped({
  required Component child,
  required List<AuthType> authTypes,
  List<OAuthProviderPublic> providers = const [],
}) {
  return ProviderScope(
    overrides: [
      supportedAuthTypesProvider.overrideWithValue(authTypes),
      oauthProvidersProvider.overrideWithValue(providers),
      appNameProvider.overrideWithValue('Zonai'),
      hasBrandLogoProvider.overrideWithValue(false),
    ],
    child: child,
  );
}

void main() {
  group('an OAuth-only admin table', () {
    testComponents('offers one button per provider the table declares', (tester) async {
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(token: 'invite-token', onSelectProvider: (_) {}),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
        ),
      );

      expect(find.text('Accept your invite'), findsOneComponent);
      expect(find.text('Sign in with Google'), findsOneComponent);
      // The one thing the invitee has to know: a different account will not do.
      expect(find.textContaining('has to match the invited one'), findsOneComponent);
    });

    testComponents('hands the chosen provider to its caller', (tester) async {
      final chosen = <String>[];
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(token: 'invite-token', onSelectProvider: (p) => chosen.add(p.id)),
          authTypes: const [AuthType.oauth],
          providers: [
            _provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google),
            _provider(id: 'github', displayName: 'GitHub', kind: OAuthProviderKind.github),
          ],
        ),
      );

      await tester.click(find.componentWithText(button, 'Sign in with GitHub'));

      expect(chosen, ['github']);
    });

    testComponents('reads the token out of the URL and nowhere else', (tester) async {
      // The wired screen, so the path from `?token=` to the buttons is the one
      // exercised. Nothing asserts the token is rendered, because it must not
      // be: it appears only in the URL this page navigates to.
      tester.pumpComponent(
        _scoped(
          child: const AdminInviteAcceptScreen(),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
        ),
      );

      expect(find.text('Sign in with Google'), findsOneComponent);
      expect(find.textContaining('tok_abc123'), findsNothing);
    }, url: '/_/admin/invite?token=tok_abc123');
  });

  group('a password admin table', () {
    testComponents('says what it can and cannot do, and offers no provider', (tester) async {
      // Design §3.3 wants a set-password form here. There is no route to post
      // one to: `startAdminInviteOAuth` is the only acceptance entry point the
      // db mutator exposes (`auth_controller.dart` says so itself). A form
      // that submitted nowhere would look exactly like the feature, so this
      // says what is true and names the path that does work.
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(token: 'invite-token', onSelectProvider: (_) {}),
          authTypes: const [AuthType.password],
        ),
      );

      expect(find.textContaining('an email and password'), findsOneComponent);
      expect(find.textContaining('zonai db admin add'), findsOneComponent);
      expect(find.textContaining('Sign in with'), findsNothing);
    });

    testComponents('names every method the table declares', (tester) async {
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(token: 'invite-token', onSelectProvider: (_) {}),
          authTypes: const [AuthType.password, AuthType.otp, AuthType.magicLink],
        ),
      );

      expect(find.textContaining('an email and password, a one-time email code or a magic link'), findsOneComponent);
    });

    testComponents('a table that also allows OAuth still gets its buttons', (tester) async {
      // The invite belongs to the table, and this table's OAuth half can
      // accept it -- so the page leads with what works and is honest about
      // the rest rather than refusing outright.
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(token: 'invite-token', onSelectProvider: (_) {}),
          authTypes: const [AuthType.password, AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
        ),
      );

      expect(find.text('Sign in with Google'), findsOneComponent);
      expect(find.textContaining('only be accepted with a provider today'), findsOneComponent);
    });
  });

  group('a link that cannot be accepted', () {
    testComponents('a missing token gets an explanation and no way to guess further', (tester) async {
      tester.pumpComponent(
        _scoped(
          child: const AdminInviteAcceptView(token: null, onSelectProvider: _ignore),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
        ),
      );

      expect(find.text('This invite link is not complete'), findsOneComponent);
      // No provider button, no form, no retry: every one of them would be an
      // invitation to try again with something guessed.
      expect(find.textContaining('Sign in with'), findsNothing);
      // And nothing that answers "does an invite for that address exist?".
      expect(find.textContaining('expired'), findsNothing);
      expect(find.textContaining('revoked'), findsNothing);
    });

    testComponents('a blank token is a missing one', (tester) async {
      tester.pumpComponent(
        _scoped(
          child: const AdminInviteAcceptScreen(),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
        ),
      );

      expect(find.text('This invite link is not complete'), findsOneComponent);
    }, url: '/_/admin/invite?token=%20%20');

    testComponents('an app with no auth methods says so instead of offering nothing', (tester) async {
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(token: 'invite-token', onSelectProvider: (_) {}),
          authTypes: const [],
        ),
      );

      expect(find.text('Invites cannot be accepted yet'), findsOneComponent);
    });
  });

  group('the token', () {
    test('is read from the query string, and only when it is really there', () {
      expect(inviteTokenFromUrl('/_/admin/invite?token=tok_abc'), 'tok_abc');
      expect(inviteTokenFromUrl('http://localhost:8080/_/admin/invite?token=tok_abc'), 'tok_abc');
      expect(inviteTokenFromUrl('/_/admin/invite'), isNull);
      expect(inviteTokenFromUrl('/_/admin/invite?token='), isNull);
      expect(inviteTokenFromUrl('/_/admin/invite?token=%20'), isNull);
    });

    test('reaches the invite start route, and not either of the other two', () {
      final url = AuthRoutes.oauthInviteStartUrl('google', 'tok abc/+1');

      expect(url, startsWith('/auth/admin/invite/oauth/start/google?'));
      // Encoded, because the server reads it back with `Uri.queryParameters`:
      // a raw `+` there decodes to a space and names no invite.
      expect(url, contains('token=tok+abc%2F%2B1'));
      expect(url, contains('redirect_to=%2F_%2Fauth%2Foauth%2Fcallback'));
      // Not `/auth/oauth/start/:provider` (auto-provisions into whatever
      // `?table=` says) and not `/auth/admin/oauth/start/:provider` (needs an
      // admin bearer token this visitor does not have).
      expect(url, isNot(contains('table=')));
      expect(url, isNot(AuthRoutes.oauthAdminStartUrl('google')));
    });
  });

  group('the route', () {
    test('is public — reachable with no session, which is the whole point', () {
      expect(AuthRoutes.isAdminInviteAcceptPath('/admin/invite'), isTrue);
      expect(AuthRoutes.isAdminInviteAcceptPath('/_/admin/invite'), isTrue);
      expect(AuthRoutes.isAdminInviteAcceptPath('/_/admin/invite?token=tok_abc'), isTrue);
      expect(AuthRoutes.isPublicAuthPath('/_/admin/invite?token=tok_abc'), isTrue);
    });

    test('is not a sign-in path', () {
      // `isSignInPath` is what bounces a SIGNED-IN visitor away and what
      // `backPath` reads. Being public is not the same as being a sign-in page.
      expect(AuthRoutes.isSignInPath('/admin/invite'), isFalse);
      expect(AuthRoutes.backPath('/admin/invite', const [AuthType.oauth]), isNull);
    });
  });
}

void _ignore(OAuthProviderPublic provider) {}
