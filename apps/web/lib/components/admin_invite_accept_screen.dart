import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_routes.dart';
import '../providers/admin_invite_probe_provider.dart';
import '../utils/admin_invite_status.dart';
import '../utils/table_cell_edit.dart';
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
      onAccept: ({password, values}) async {
        if (token == null) return;
        await context.read(adminInviteAcceptProvider)(token, password: password, values: values);
        // The token is already stored by the client's X-Auth interceptor;
        // this is what makes the app *notice*, and it is what navigates to
        // the dashboard. Same call `signInWithPassword` makes after its own
        // request, so an invited admin lands exactly where a returning one
        // does.
        await context.read(authProvider.notifier).signIn();
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
    required this.onAccept,
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

  /// Accepts the invite directly (design §3.3). Completes when the account
  /// exists and the session is stored, or throws with something to show.
  ///
  /// Never called for a collection that declares OAuth and nothing else — the
  /// form that would call it is not rendered there, and the runtime refuses
  /// that combination regardless.
  final Future<void> Function({String? password, Map<String, dynamic>? values}) onAccept;

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

    final direct = _otherMethods(authTypes);
    final hasOAuth = authTypes.contains(AuthType.oauth);

    return SignInScreen(
      tagline: 'Accept your admin invite',
      child: AuthFormCard(
        children: [
          const ZonaiPageTitle('Accept your invite'),
          ZonaiPageSubtitle(
            hasOAuth
                // The address check is real and only on the provider path, so
                // it is only promised there. Saying it unconditionally would
                // describe the direct path as doing something it does not:
                // there, the token *is* the proof of the address, because it
                // was mailed to that address and nowhere else.
                ? 'Continue with the account this invitation was sent to. The address on the '
                      'account has to match the invited one — signing in with a different account '
                      'will not accept the invite.'
                : 'Accepting creates your admin account for the address this invitation was sent '
                      'to, and signs you in.',
          ),
          if (direct.isNotEmpty)
            AdminInviteAcceptForm(
              needsPassword: authTypes.contains(AuthType.password),
              methods: direct,
              fields: (status as AdminInviteLive).fields,
              onAccept: onAccept,
            ),
          if (direct.isNotEmpty && hasOAuth) p(classes: 'z-admins-note', [.text('Or accept with a provider:')]),
          if (hasOAuth) OAuthProviderButtons(onSelect: onSelectProvider),
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

/// The direct-acceptance form (design §3.3): set a password if the collection
/// signs in with one, then accept.
///
/// **No email field.** The address is the invite's, read server-side from the
/// challenge row — a field here would be one the invitee could disagree with,
/// on the one decision they must not get to make.
class AdminInviteAcceptForm extends StatefulComponent {
  const AdminInviteAcceptForm({
    super.key,
    required this.needsPassword,
    required this.methods,
    required this.fields,
    required this.onAccept,
  });

  /// True when the collection declares `PasswordAuth`. The server decides this
  /// too and refuses a mismatch either way; this only decides what to show.
  final bool needsPassword;

  /// The non-OAuth methods the collection declares, for the sentence that
  /// tells someone how they will sign in next time.
  final List<AuthType> methods;

  /// Columns the account needs beyond email and password. Rendered as text
  /// inputs in the order the schema declares them, which is the order the
  /// dashboard's own create form uses.
  final List<ColumnShape> fields;

  final Future<void> Function({String? password, Map<String, dynamic>? values}) onAccept;

  @override
  State<AdminInviteAcceptForm> createState() => AdminInviteAcceptFormState();
}

class AdminInviteAcceptFormState extends State<AdminInviteAcceptForm> {
  String _password = '';
  String _confirm = '';
  final Map<String, String> _values = {};
  bool _submitting = false;
  String? _error;

  /// Fields the schema will not accept as empty.
  ///
  /// [isCreateFieldRequired] is the dashboard's own create-form rule, reused
  /// rather than re-derived. It is safe to apply here because the server has
  /// already narrowed the list to admin-creatable columns, so the only
  /// question left is the one this asks: non-nullable, and not a kind that
  /// has a sensible empty value.
  Iterable<ColumnShape> get _requiredFields => component.fields.where(isCreateFieldRequired);

  /// Checked here only to spare a round trip and to say *which* rule was
  /// missed. The server enforces the password rules regardless — this is a
  /// convenience, and treating it as the gate is how a rule ends up living
  /// only in the browser.
  String? get _localRefusal {
    for (final field in _requiredFields) {
      if ((_values[field.name] ?? '').trim().isEmpty) {
        return '${columnShapeHeaderLabel(field)} is required.';
      }
    }
    if (!component.needsPassword) return null;
    if (_password.isEmpty) return 'Choose a password to finish setting up your account.';
    if (_password != _confirm) return 'The two passwords do not match.';
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;

    if (_localRefusal case final refusal?) {
      setState(() => _error = refusal);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await component.onAccept(
        password: component.needsPassword ? _password : null,
        // Only what was actually typed. Sending empty strings for untouched
        // optional columns would write "" over a column whose default is the
        // better answer.
        values: {
          for (final entry in _values.entries)
            if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
        },
      );
      // Deliberately no success state and no `_submitting = false`. A
      // successful acceptance navigates away, and re-enabling the button in
      // the frames before that lands invites a second submit on a token that
      // is now spent -- which would answer with the "no longer usable" screen
      // on an acceptance that in fact worked.
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // The server's own message. Its refusals here are written for this
        // reader -- "this table accepts invites through a provider only",
        // "requires a password" -- and paraphrasing them into one house
        // sentence is how the actionable half gets lost.
        _error = '$error';
      });
    }
  }

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      if (_error case final message?) ZonaiErrorAlert(title: 'Could not accept the invitation', body: message),
      for (final field in component.fields)
        ZonaiTextField(
          id: 'admin-invite-field-${field.name}',
          fieldLabel: columnShapeHeaderLabel(field),
          value: _values[field.name] ?? '',
          disabled: _submitting,
          onInput: (value) => setState(() => _values[field.name] = value),
        ),
      if (component.needsPassword) ...[
        ZonaiTextField(
          id: 'admin-invite-password',
          fieldLabel: 'Choose a password',
          value: _password,
          type: InputType.password,
          autocomplete: 'new-password',
          disabled: _submitting,
          onInput: (value) => setState(() => _password = value),
        ),
        ZonaiTextField(
          id: 'admin-invite-password-confirm',
          fieldLabel: 'Confirm password',
          value: _confirm,
          type: InputType.password,
          autocomplete: 'new-password',
          disabled: _submitting,
          onInput: (value) => setState(() => _confirm = value),
        ),
      ] else
        p(classes: 'z-admins-note', [
          .text(
            'You will sign in with ${AdminInviteAcceptView._methodsSentence(component.methods)} '
            'from now on, at the address this invitation was sent to.',
          ),
        ]),
      ZonaiButton(
        fullWidth: true,
        disabled: _submitting,
        onClick: _submit,
        child: .text(_submitting ? 'Accepting…' : 'Accept invitation'),
      ),
    ]);
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
