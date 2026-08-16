import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_routes.dart';
import '../providers/admin_invite_probe_provider.dart';
import '../utils/admin_invite_status.dart';
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
///
/// Stateful because the one thing this screen could not previously answer —
/// *is this link still good?* — is a round trip. Before the probe existed the
/// only judge of a token was `GET /auth/admin/invite/oauth/start/:provider`,
/// reached by leaving the SPA, so a week-old link's first impression was that
/// route's raw 401 (design §7). Asking first means the explanation below is
/// this screen's, in the same voice it already refuses a missing token in.
class AdminInviteAcceptScreen extends StatefulComponent {
  const AdminInviteAcceptScreen({super.key});

  @override
  State<AdminInviteAcceptScreen> createState() => AdminInviteAcceptScreenState();
}

class AdminInviteAcceptScreenState extends State<AdminInviteAcceptScreen> {
  AdminInviteStatus _status = const AdminInviteChecking();

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_probe);
  }

  /// Client-only, like every other async load here (`adminMembersProvider`
  /// says the same about itself): the server render has nothing to repaint
  /// once an answer arrives, so SSR stays on [AdminInviteChecking] and the
  /// browser resolves it.
  ///
  /// A missing token never reaches the network. There is nothing to ask
  /// about, and asking anyway would spend a request from the shared
  /// invite-acceptance rate-limit bucket on every truncated copy-paste.
  Future<void> _probe() async {
    if (!context.binding.isClient) return;

    final token = inviteTokenFromUrl(context.url);
    if (token == null) return;

    final status = await context.read(adminInviteProbeProvider)(token);

    if (!mounted) return;
    setState(() => _status = status);
  }

  @override
  Component build(BuildContext context) {
    final token = inviteTokenFromUrl(context.url);

    return AdminInviteAcceptView(
      token: token,
      status: _status,
      onSelectProvider: (provider) {
        if (token == null) return;
        startAdminInviteOAuthFlow(provider: provider, token: token);
      },
    );
  }
}

/// The acceptance page as a function of the token, the probe's verdict, and
/// the methods the admin collection declares.
///
/// Split out from [AdminInviteAcceptScreen] so a test can pump it for an
/// OAuth-only collection, a password collection, a dead link and a broken one
/// without a browser to navigate or a server to answer — the navigation is
/// the caller's [onSelectProvider] and the round trip is the caller's
/// [status].
class AdminInviteAcceptView extends StatelessComponent {
  const AdminInviteAcceptView({
    super.key,
    required this.token,
    required this.onSelectProvider,
    this.status = const AdminInviteChecking(),
  });

  final String? token;

  /// What `GET /auth/admin/invite?token=` said about [token].
  ///
  /// The methods rendered below come from here rather than from
  /// `supportedAuthTypesProvider`, which is the union across *every* admin
  /// table. The probe names the one table this invite is actually for.
  final AdminInviteStatus status;

  final void Function(OAuthProviderPublic provider) onSelectProvider;

  @override
  Component build(BuildContext context) {
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

    if (status is AdminInviteChecking) {
      return const _InviteMessage(
        title: 'Checking your invitation',
        body: 'One moment — we are looking up the invitation this link is for.',
      );
    }

    if (status is AdminInviteUnusable) {
      return const _InviteMessage(
        title: 'This invite link can no longer be used',
        // Names the possibilities and commits to none of them, because the
        // server does not say which and must not: an answer that told
        // "expired" apart from "no such invite" would let anyone holding a
        // guessed link learn whether an address has an invite pending. Same
        // reason `DELETE /admin/invites/:email` answers identically for an
        // address that was never invited.
        //
        // No retry and no provider buttons. Both would send a dead token to
        // the start route, which is the raw 401 this screen exists to spare
        // the reader.
        body:
            'Invitations stop working once they are accepted, once they expire, or if whoever '
            'sent it has withdrawn it — and a link that was copied incompletely will not work '
            'either. Ask whoever invited you to send a fresh one; nothing has gone wrong with '
            'your account.',
      );
    }

    final authTypes = (status as AdminInviteLive).authTypes;

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
