import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/auth/oauth_providers_provider.dart';
import 'package:zonai_web/auth/supported_auth_types_provider.dart';
import 'package:zonai_web/components/oauth_sign_in_screen.dart';
import 'package:zonai_web/components/sign_in_screen.dart';
import 'package:zonai_web/providers/app_name_provider.dart';
import 'package:zonai_web/providers/brand_logo_provider.dart';

OAuthProviderPublic _provider({
  required String id,
  required String displayName,
  OAuthProviderKind kind = OAuthProviderKind.custom,
  String table = 'users',
}) {
  return OAuthProviderPublic(
    id: id,
    displayName: displayName,
    table: table,
    kind: kind,
    startPath: '/auth/oauth/start/$id?table=$table',
  );
}

/// Wraps [child] in the provider overrides SSR would have installed, so a
/// screen can be pumped without the whole `AuthAppShell` client island.
Component _scoped({
  required Component child,
  required List<AuthType> authTypes,
  required List<OAuthProviderPublic> providers,
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
  group('AuthTypePickerScreen with OAuth', () {
    testComponents('lists one button per provider alongside the other method tiles', (tester) async {
      tester.pumpComponent(
        _scoped(
          child: const AuthTypePickerScreen(),
          authTypes: const [AuthType.password, AuthType.oauth],
          providers: [
            _provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google),
            _provider(id: 'github', displayName: 'GitHub', kind: OAuthProviderKind.github),
            _provider(id: 'apple', displayName: 'Apple', kind: OAuthProviderKind.apple),
          ],
        ),
      );

      expect(find.text('Sign in with Google'), findsOneComponent);
      expect(find.text('Sign in with GitHub'), findsOneComponent);
      expect(find.text('Sign in with Apple'), findsOneComponent);
      // The password tile is still a tile — OAuth did not replace the list.
      expect(find.text('Email & password'), findsOneComponent);
      // …and OAuth is a heading over the buttons, not a fourth tile that
      // navigates somewhere.
      expect(find.text('Continue with a provider'), findsOneComponent);
    });

    testComponents('renders a provider whose kind zonai has never heard of', (tester) async {
      tester.pumpComponent(
        _scoped(
          child: const AuthTypePickerScreen(),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'acme', displayName: 'Acme SSO')],
        ),
      );

      expect(find.text('Sign in with Acme SSO'), findsOneComponent);
      // No bundled mark exists for `custom`, so `OAuthProviderIcon` falls all
      // the way through to its letter tile rather than rendering nothing.
      expect(find.text('A'), findsOneComponent);
    });

    testComponents('says so when the provider list came back empty', (tester) async {
      tester.pumpComponent(
        _scoped(child: const AuthTypePickerScreen(), authTypes: const [AuthType.oauth], providers: const []),
      );

      expect(find.text('No sign-in providers are available right now.'), findsOneComponent);
    });
  });

  group('OAuthSignInScreen — the OAuth-only collection', () {
    testComponents('is a usable sign-in page on its own', (tester) async {
      tester.pumpComponent(
        _scoped(
          child: const OAuthSignInScreen(),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
        ),
      );

      expect(find.text('Sign in'), findsOneComponent);
      expect(find.text('Sign in with Google'), findsOneComponent);
      // Single auth type: nothing to go back to, so no back control.
      expect(find.text('← Back'), findsNothing);
    });

    testComponents('hands the clicked provider to its caller', (tester) async {
      final selected = <String>[];
      tester.pumpComponent(
        _scoped(
          child: OAuthProviderButtons(onSelect: (provider) => selected.add(provider.id)),
          authTypes: const [AuthType.oauth],
          providers: [
            _provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google),
            _provider(id: 'acme', displayName: 'Acme SSO'),
          ],
        ),
      );

      await tester.click(find.byComponentPredicate((c) => c is button).at(1));

      expect(selected, ['acme']);
    });
  });
}
