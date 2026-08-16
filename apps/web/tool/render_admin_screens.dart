// Renders the admin-invite dashboard screens to standalone HTML files so they
// can be screenshotted without booting the whole zonai stack.
//
// Companion to `render_oauth_screens.dart`, and the same caveat applies: the
// member list and provider list are supplied directly rather than fetched from
// a live server. Everything downstream of them -- `AdminsPanel`,
// `AdminInviteAcceptView`, the provider buttons, the bundled brand marks and
// every style rule -- is the real component tree SSR renders in production, via
// the same `renderComponent` entry point `main.server.dart` uses.
//
// The cases below are chosen to show the decisions rather than the happy path:
// a disabled control with its reason, an empty state, and an admin table that
// cannot accept invites at all.
//
//   dart run tool/render_admin_screens.dart <output-dir>
import 'dart:convert';
import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/app.dart';
import 'package:zonai_web/auth/oauth_providers_provider.dart';
import 'package:zonai_web/auth/supported_auth_types_provider.dart';
import 'package:zonai_web/components/admin_invite_accept_screen.dart';
import 'package:zonai_web/components/admins_screen.dart';
import 'package:zonai_web/components/oauth_sign_in_screen.dart';
import 'package:zonai_web/components/theme/oauth_button.dart';
import 'package:zonai_web/components/theme/ui_styles.dart';
import 'package:zonai_web/constants/theme.dart' hide styles;
import 'package:zonai_web/constants/theme.dart' as theme show styles;
import 'package:zonai_web/providers/app_name_provider.dart';
import 'package:zonai_web/providers/brand_logo_provider.dart';
import 'package:zonai_web/utils/admin_invite_status.dart';
import 'package:zonai_web/utils/admin_members.dart';

/// Fixed so a re-render produces byte-identical output. A screenshot that
/// changes every run is a screenshot nobody can diff.
final _now = DateTime.utc(2026, 8, 16, 12);

OAuthProviderPublic _provider(String id, String displayName, OAuthProviderKind kind) {
  return OAuthProviderPublic(
    id: id,
    displayName: displayName,
    table: 'users',
    kind: kind,
    startPath: '/auth/oauth/start/$id?table=users',
  );
}

final _google = _provider('google', 'Google', OAuthProviderKind.google);
final _github = _provider('github', 'GitHub', OAuthProviderKind.github);

AdminMember _admin(String email) => AdminMember(email: email, label: email, row: {'email': email});

Future<void> _write(String outPath, ResponseLike response) async {
  final file = File(outPath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(response.body);
  stdout.writeln('wrote $outPath (${response.body.length} bytes)');

  // The same render pinned to light mode. Worth capturing separately: the
  // disabled-control styling and the provider marks both have to hold on a
  // light ground, which a dark-only capture cannot show.
  final light = utf8.decode(response.body).replaceFirst('<html>', '<html data-theme="light">');
  final lightPath = outPath.replaceFirst('.html', '-light.html');
  await File(lightPath).writeAsString(light);
  stdout.writeln('wrote $lightPath');
}

/// Every stylesheet the real document pulls in, so the capture is styled the
/// way the dashboard actually is rather than as bare markup.
///
/// The two new screens deliberately have no `@css` getters of their own: a new
/// one is inert until `main.server.options.dart` is regenerated, so their rules
/// live in `zonaiUiStyles`, which is already listed here.
List<StyleRule> get _styles => [
  ...theme.styles,
  ...zonaiUiStyles,
  ...oauthButtonStyles,
  ...App.styles,
  ...OAuthProviderButtons.styles,
];

Future<void> _renderAdmins({
  required AdminMembers members,
  required String? signedInEmail,
  required String outPath,
}) async {
  final response = await renderComponent(
    Document(
      styles: _styles,
      head: [
        script(content: themeBootstrapScript),
        meta(name: 'viewport', content: 'width=device-width, initial-scale=1'),
      ],
      body: ProviderScope(
        overrides: [appNameProvider.overrideWithValue('Banana'), hasBrandLogoProvider.overrideWithValue(false)],
        child: div(classes: 'app-root', [
          div(classes: 'dashboard-content', [
            AdminsPanel(
              members: members,
              signedInEmail: signedInEmail,
              now: _now,
              inviteEmail: '',
              onInviteEmailChanged: (_) {},
              onInvite: (_) {},
              onRevoke: (_) {},
              onRemove: (_) {},
            ),
          ]),
        ]),
      ),
    ),
  );
  await _write(outPath, response);
}

Future<void> _renderAccept({
  required List<AuthType> authTypes,
  required List<OAuthProviderPublic> providers,
  required String? token,
  required String outPath,
  AdminInviteStatus? status,
  List<ColumnShape> fields = const [],
}) async {
  final response = await renderComponent(
    Document(
      styles: _styles,
      head: [
        script(content: themeBootstrapScript),
        meta(name: 'viewport', content: 'width=device-width, initial-scale=1'),
      ],
      // Pumped directly rather than through the whole App: the app path
      // renders only a client-island placeholder here, exactly as
      // render_oauth_screens.dart documents.
      body: ProviderScope(
        overrides: [
          supportedAuthTypesProvider.overrideWithValue(authTypes),
          oauthProvidersProvider.overrideWithValue(providers),
          appNameProvider.overrideWithValue('Banana'),
          hasBrandLogoProvider.overrideWithValue(false),
        ],
        child: div(classes: 'app-root', [
          AdminInviteAcceptView(
            token: token,
            // The probe's verdict is supplied here for the same reason the
            // member list is: this renders the screen, not the round trip.
            // Defaulting to "live with these methods" keeps every pre-existing
            // case rendering exactly what it did before the probe landed.
            status:
                status ??
                AdminInviteLive(
                  table: 'staff',
                  authTypes: authTypes,
                  fields: fields,
                ),
            onSelectProvider: (_) {},
            // Renders the form; never submits it. These pages are static
            // output, so an acceptance that actually ran would be a round
            // trip this tool has no server for.
            onAccept: ({String? password, Map<String, dynamic>? values}) async {},
          ),
        ]),
      ),
    ),
  );
  await _write(outPath, response);
}

/// The non-nullable column the reference schema has beyond email and password.
/// Acceptance cannot create the row without it, so the form has to ask.
const _requiredName = ColumnShape(
  name: 'name',
  kind: ColumnShapeKind.text,
  isNullable: false,
  isPrimaryKey: false,
  autoIncrement: false,
  sqlType: 'TEXT',
);

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/render_admin_screens.dart <out-dir>');
    exitCode = 64;
    return;
  }
  final out = args.first;

  Jaspr.initializeApp(useIsolates: false);

  // Two admins and a pending invite, viewed by one of the admins. Shows the
  // pending row with its expiry, and Remove disabled on your own account --
  // design §4 item 6's first half, as a state rather than as an error.
  await _renderAdmins(
    members: AdminMembers(
      admins: [_admin('ada@example.com'), _admin('grace@example.com')],
      invites: [
        PendingInvite(
          email: 'katherine@example.com',
          invitedAt: _now.subtract(const Duration(days: 1)),
          expiresAt: _now.add(const Duration(days: 6)),
          invitedByEmail: 'ada@example.com',
        ),
      ],
    ),
    signedInEmail: 'ada@example.com',
    outPath: '$out/admins-with-pending-invite.html',
  );

  // The sole admin, no invites. Remove is disabled for the other half of §4
  // item 6 -- a dashboard that can lock everyone out of itself is a bug -- and
  // the invite form is the only way forward, which is the point of the screen.
  await _renderAdmins(
    members: AdminMembers(admins: [_admin('ada@example.com')], invites: []),
    signedInEmail: 'ada@example.com',
    outPath: '$out/admins-sole-admin.html',
  );

  // Accepting on a Google-only admin table: one button, no vestigial
  // "choose a method" step.
  await _renderAccept(
    authTypes: const [AuthType.oauth],
    providers: [_google],
    token: 'invite-token',
    outPath: '$out/admin-invite-accept-oauth.html',
  );

  // The same link on a password-only admin table (design §3.3). A real
  // set-password form now, where this case used to be an explanation pointing
  // at `zonai db admin add`. Carries a required `name`, because the reference
  // schema has one and a form that asked only for a password is precisely the
  // shape that failed on the insert.
  await _renderAccept(
    authTypes: const [AuthType.password],
    providers: const [],
    token: 'invite-token',
    fields: [_requiredName],
    outPath: '$out/admin-invite-accept-password.html',
  );

  // An OTP admin table: nothing to fill in but the columns the row needs, and
  // an accept button. No password field, because there is no password column
  // to put one in -- the runtime refuses a password sent to such a table.
  await _renderAccept(
    authTypes: const [AuthType.otp],
    providers: const [],
    token: 'invite-token',
    fields: [_requiredName],
    outPath: '$out/admin-invite-accept-otp.html',
  );

  // A table offering both. The direct form leads and the provider buttons sit
  // under it -- one invite, two ways to accept, neither hidden behind the
  // other.
  await _renderAccept(
    authTypes: const [AuthType.password, AuthType.oauth],
    providers: [_google],
    token: 'invite-token',
    fields: [_requiredName],
    outPath: '$out/admin-invite-accept-both.html',
  );

  // A link with no token at all -- a truncated copy-paste, which is the most
  // common way this screen is reached in error.
  await _renderAccept(
    authTypes: const [AuthType.oauth],
    providers: [_google, _github],
    token: null,
    outPath: '$out/admin-invite-accept-no-token.html',
  );

  // A token the server will not accept -- opened a week late, revoked, or
  // guessed. This is the state design §7 exists for: before the liveness
  // probe, reaching it meant leaving the SPA and landing on a raw 401 from
  // `/auth/admin/invite/oauth/start/:provider`. Note what is absent as much
  // as what is present: no provider button, no retry, and no word about
  // WHICH of the reasons applies -- the server does not say, on purpose.
  await _renderAccept(
    authTypes: const [AuthType.oauth],
    providers: [_google],
    token: 'invite-token',
    status: const AdminInviteUnusable(),
    outPath: '$out/admin-invite-accept-expired.html',
  );

  // The moment before that answer arrives. Worth capturing because it is what
  // SSR renders for every visitor: if this state offered the sign-in buttons,
  // the probe would be decorative -- someone with a dead link would click
  // through to the 401 before the check ever came back.
  await _renderAccept(
    authTypes: const [AuthType.oauth],
    providers: [_google],
    token: 'invite-token',
    status: const AdminInviteChecking(),
    outPath: '$out/admin-invite-accept-checking.html',
  );
}
