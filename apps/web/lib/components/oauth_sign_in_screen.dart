import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_routes.dart';
import '../auth/oauth_providers_provider.dart';
import '../constants/spacing.dart';
import 'sign_in_screen.dart';
import 'theme/oauth_button.dart';
import 'theme/theme_components.dart';

/// Leaves the SPA for the server route that begins [provider]'s OAuth flow.
///
/// A full-page assign, not [AppNavigation.goApp]: the very next hop is the
/// provider's own domain, so there is no client-side route to push.
///
/// Deliberately [AuthRoutes.oauthAdminStartUrl] and not
/// [AuthRoutes.oauthStartUrl]: this is the admin dashboard, and the public
/// start route auto-provisions a first-seen identity into whatever `table` it
/// is handed — which, for the `AsAdmin` collection, mints a full admin.
void startOAuthFlow(OAuthProviderPublic provider) {
  web.window.location.assign(AuthRoutes.oauthAdminStartUrl(provider.id));
}

/// One [OAuthProviderButton] per provider the schema declares.
///
/// Carries no navigation of its own for the same reason [OAuthProviderButton]
/// does not — [onSelect] is supplied by the caller, which is what lets a test
/// observe a click without a browser to navigate.
class OAuthProviderButtons extends StatelessComponent {
  const OAuthProviderButtons({super.key, required this.onSelect});

  final void Function(OAuthProviderPublic provider) onSelect;

  @override
  Component build(BuildContext context) {
    final providers = context.watch(oauthProvidersProvider);

    // Reachable: `AuthType.oauth` comes from the admin table's own
    // `authTypes`, while the provider list comes from a separate SSR call
    // that answers empty when the Zonai worker is not up yet. Saying so beats
    // rendering an empty div the developer has to guess about.
    if (providers.isEmpty) {
      return const ZonaiErrorText('No sign-in providers are available right now.');
    }

    return div(classes: 'z-oauth-providers', [
      for (final provider in providers) OAuthProviderButton(provider: provider, onClick: () => onSelect(provider)),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css(
      '.z-oauth-providers',
    ).styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s8), width: 100.percent),
  ];
}

/// Sign-in screen for `/sign-in/oauth` — the whole page when OAuth is the only
/// method the admin collection declares.
class OAuthSignInScreen extends StatelessComponent {
  const OAuthSignInScreen({super.key});

  @override
  Component build(BuildContext context) {
    return SignInScreen(
      tagline: 'Choose how you want to sign in',
      child: AuthFormCard(
        children: [
          const ZonaiPageTitle('Sign in'),
          const ZonaiPageSubtitle('Continue with one of the providers below.'),
          OAuthProviderButtons(onSelect: startOAuthFlow),
        ],
      ),
    );
  }
}
