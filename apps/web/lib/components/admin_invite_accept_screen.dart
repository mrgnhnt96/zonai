import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_routes.dart';
import '../auth/supported_auth_types_provider.dart';
import 'oauth_sign_in_screen.dart';
import 'sign_in_screen.dart';
import 'theme/theme_components.dart';

/// The invite token from `/_/admin/invite?token=…`, or null when the link
/// carries none.
///
/// The token lives in the URL and nowhere else. It is read here, handed
/// straight to [AuthRoutes.oauthInviteStartUrl], and never rendered, never put
/// in the page title (`PageTitle` switches on the path, which
/// `AuthRoutes.normalizePath` has already stripped of its query), and never
/// written to storage. A token in a title is a token in the browser history
/// entry and in every screenshot of the tab.
String? inviteTokenFromUrl(String url) {
  final token = Uri.parse(url).queryParameters['token'];
  if (token == null || token.trim().isEmpty) return null;
  return token;
}

/// Leaves the SPA for the server route that accepts this invite through
/// [provider] (`docs/admin-invite-design.md` §3.2).
///
/// A full-page assign, like [startOAuthFlow]: the next hop is the provider's
/// own domain. Deliberately the *invite* start route — [startOAuthFlow]'s
/// admin route requires a bearer token this visitor does not have, and the
/// public one auto-provisions a first-seen identity into whatever table it is
/// handed, which for an `AsAdmin` collection would hand out an admin account
/// to whoever opened the link.
void startAdminInviteOAuthFlow({required OAuthProviderPublic provider, required String token}) {
  web.window.location.assign(AuthRoutes.oauthInviteStartUrl(provider.id, token));
}

/// Where the invite email's link lands (design §3.2, §3.3).
///
/// Reachable with no session at all, which is the entire point — see
/// [AuthRoutes.isPublicAuthPath].
class AdminInviteAcceptScreen extends StatelessComponent {
  const AdminInviteAcceptScreen({super.key});

  @override
  Component build(BuildContext context) {
    final token = inviteTokenFromUrl(context.url);

    return AdminInviteAcceptView(
      token: token,
      onSelectProvider: (provider) {
        if (token == null) return;
        startAdminInviteOAuthFlow(provider: provider, token: token);
      },
    );
  }
}

/// The acceptance page as a function of the token and the methods the admin
/// collection declares.
///
/// Split out from [AdminInviteAcceptScreen] so a test can pump it for an
/// OAuth-only collection, a password collection and a broken link without a
/// browser to navigate — the navigation is the caller's [onSelectProvider].
class AdminInviteAcceptView extends StatelessComponent {
  const AdminInviteAcceptView({super.key, required this.token, required this.onSelectProvider});

  final String? token;
  final void Function(OAuthProviderPublic provider) onSelectProvider;

  @override
  Component build(BuildContext context) {
    // The methods the *admin table* declares, seeded by SSR from
    // `zonaiDB.adminSupportedAuthTypes()`. Design §3.3 is explicit that the
    // invite belongs to the table, not to OAuth, so this screen asks the table
    // rather than assuming a provider list exists.
    final authTypes = context.watch(supportedAuthTypesProvider);

    if (token == null) {
      return const _InviteMessage(
        title: 'This invite link is not complete',
        // Says what is wrong with the link and nothing about whether any
        // invite exists. A message that distinguished "no such invite" from
        // "expired" would answer, for any address someone cared to try,
        // whether that address has one pending.
        body:
            'The link you followed is missing its invite token, so there is nothing here to '
            'accept. Open the link from the invitation email directly, or ask whoever invited '
            'you to send a new one.',
      );
    }

    if (authTypes.isEmpty) {
      return const _InviteMessage(
        title: 'Invites cannot be accepted yet',
        body:
            'This app has no authentication methods configured, so there is no way to sign in '
            'as the admin this invite is for. Add an auth extension and ask for a fresh invite.',
      );
    }

    if (!authTypes.contains(AuthType.oauth)) {
      return _InviteMessage(
        title: 'This invite has to be accepted by an administrator',
        body:
            'Admin accounts here sign in with ${_methodsSentence(authTypes)}, and accepting an '
            'invite that way is not available in the browser yet — only a provider sign-in is. '
            'Ask whoever invited you to create the account directly with "zonai db admin add"; '
            'your invite link cannot finish on its own.',
      );
    }

    return SignInScreen(
      tagline: 'Accept your admin invite',
      child: AuthFormCard(
        children: [
          const ZonaiPageTitle('Accept your invite'),
          const ZonaiPageSubtitle(
            'Continue with the account this invitation was sent to. The address on the account '
            'has to match the invited one — signing in with a different account will not accept '
            'the invite.',
          ),
          OAuthProviderButtons(onSelect: onSelectProvider),
          if (_otherMethods(authTypes) case final others when others.isNotEmpty)
            p(classes: 'z-admins-note', [
              .text(
                'This dashboard also allows ${_methodsSentence(others)}, but an invite can only '
                'be accepted with a provider today.',
              ),
            ]),
        ],
      ),
    );
  }

  static List<AuthType> _otherMethods(List<AuthType> authTypes) {
    return [
      for (final type in authTypes)
        if (type != AuthType.oauth) type,
    ];
  }

  static String _methodsSentence(List<AuthType> authTypes) {
    final names = [for (final type in authTypes) _methodName(type)];
    if (names.isEmpty) return 'no sign-in method';
    if (names.length == 1) return names.single;
    return '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}';
  }

  static String _methodName(AuthType type) {
    return switch (type) {
      AuthType.password => 'an email and password',
      AuthType.otp => 'a one-time email code',
      AuthType.magicLink => 'a magic link',
      AuthType.oauth => 'a provider account',
    };
  }
}

/// A plain explanation and no way to guess further: no provider buttons, no
/// retry that would re-send the same dead token, nothing to fill in.
class _InviteMessage extends StatelessComponent {
  const _InviteMessage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Component build(BuildContext context) {
    return SignInScreen(
      tagline: 'Admin invitation',
      child: AuthFormCard(children: [ZonaiPageTitle(title), ZonaiPageSubtitle(body)]),
    );
  }
}
