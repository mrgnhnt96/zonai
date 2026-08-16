import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:zonai_schema/payloads.dart';
import 'package:zonai_web/auth/auth_routes.dart';
import 'package:zonai_web/auth/oauth_providers_provider.dart';
import 'package:zonai_web/auth/supported_auth_types_provider.dart';
import 'package:zonai_web/components/admin_invite_accept_screen.dart';
import 'package:zonai_web/components/theme/theme_components.dart';
import 'package:zonai_web/providers/admin_invite_probe_provider.dart';
import 'package:zonai_web/providers/app_name_provider.dart';
import 'package:zonai_web/providers/brand_logo_provider.dart';
import 'package:zonai_web/utils/admin_invite_status.dart';

/// The invite acceptance screen (`docs/admin-invite-design.md` §3.2, §3.3,
/// §7).
///
/// Two requirements meet here. §3.3's: the screen offers **the methods the
/// admin table declares**, not OAuth by assumption. And §7's: it decides
/// whether the link is still good *itself*, so a stale one gets this screen's
/// plain explanation rather than the raw 401 from
/// `/auth/admin/invite/oauth/start/:provider` that a visitor only sees after
/// the browser has already left the SPA.

OAuthProviderPublic _provider({required String id, required String displayName, required OAuthProviderKind kind}) {
  return OAuthProviderPublic(
    id: id,
    displayName: displayName,
    table: 'staff',
    kind: kind,
    startPath: '/auth/oauth/start/$id?table=staff',
  );
}

/// "The probe came back and the invite is good, on a table declaring these."
AdminInviteStatus _live(List<AuthType> authTypes, {List<ColumnShape> fields = const []}) {
  return AdminInviteLive(table: 'staff', authTypes: authTypes, fields: fields);
}

/// A required, non-nullable text column -- `name` on the reference schema,
/// and the reason acceptance needs more than a password: the insert cannot
/// invent a value the schema will not accept as null.
ColumnShape _requiredText(String name) {
  return ColumnShape(
    name: name,
    kind: ColumnShapeKind.text,
    isNullable: false,
    isPrimaryKey: false,
    autoIncrement: false,
    sqlType: 'TEXT',
  );
}

/// For the view tests that are not about acceptance. Deliberately not a
/// success: a test that reaches this without meaning to has done nothing
/// observable, rather than silently "passing" an acceptance it never wired.
Future<void> _ignoreAccept({String? password, Map<String, dynamic>? values}) async {
  throw StateError('onAccept was not expected in this test');
}

/// Types into the [ZonaiTextField] with [fieldId] by driving its `onInput`,
/// the same way `admins_screen_test.dart` drives a button through `onClick`
/// rather than dispatching a real DOM event.
Future<void> _type(ComponentTester tester, String fieldId, String value) async {
  final field =
      find
              .byComponentPredicate((c) => c is ZonaiTextField && c.id == fieldId)
              .evaluate()
              .single
              .component
          as ZonaiTextField;

  field.onInput(value);
  await tester.pump();
}

Component _scoped({
  required Component child,
  required List<AuthType> authTypes,
  List<OAuthProviderPublic> providers = const [],
  AdminInviteProbe? probe,
  AdminInviteAccept? accept,
}) {
  return ProviderScope(
    overrides: [
      supportedAuthTypesProvider.overrideWithValue(authTypes),
      oauthProvidersProvider.overrideWithValue(providers),
      appNameProvider.overrideWithValue('Zonai'),
      hasBrandLogoProvider.overrideWithValue(false),
      // Default: refuse. A test that means to exercise the accept path has to
      // say so, so a missing override can never quietly hand a wired screen
      // the sign-in buttons.
      adminInviteProbeProvider.overrideWithValue(probe ?? (_) async => const AdminInviteUnusable()),
      // Same default, same reason: an accept the test did not wire must not
      // look like one that succeeded.
      adminInviteAcceptProvider.overrideWithValue(
        accept ?? (_, {password, values}) async => throw StateError('accept was not expected in this test'),
      ),
    ],
    child: child,
  );
}

void main() {
  group('an OAuth-only admin table', () {
    testComponents('offers one button per provider the table declares', (tester) async {
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const [AuthType.oauth]),
            onSelectProvider: (_) {},
            onAccept: _ignoreAccept,
          ),
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
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const [AuthType.oauth]),
            onSelectProvider: (provider) => chosen.add(provider.id),
            onAccept: _ignoreAccept,
          ),
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
      // The wired screen, so the path from `?token=` through the probe to the
      // buttons is the one exercised. Nothing asserts the token is rendered,
      // because it must not be: it appears only in the URL this page
      // navigates to, and in the probe request it authorizes.
      final asked = <String>[];
      tester.pumpComponent(
        _scoped(
          child: const AdminInviteAcceptScreen(),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
          probe: (token) async {
            asked.add(token);
            return _live(const [AuthType.oauth]);
          },
        ),
      );
      await pumpEventQueue();

      expect(asked, ['tok_abc123']);
      expect(find.text('Sign in with Google'), findsOneComponent);
      expect(find.textContaining('tok_abc123'), findsNothing);
    }, url: '/_/admin/invite?token=tok_abc123');
  });

  group('a password admin table', () {
    testComponents('offers a set-password form, and no provider button', (tester) async {
      // Design §3.3, the half that was documented as unbuilt until the accept
      // route existed: the same link resolves to a set-password form on a
      // `PasswordAuth` table instead of an explanation and a CLI command.
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const [AuthType.password]),
            onSelectProvider: (_) {},
            onAccept: _ignoreAccept,
          ),
          authTypes: const [AuthType.password],
        ),
      );

      expect(find.text('Choose a password'), findsOneComponent);
      expect(find.text('Confirm password'), findsOneComponent);
      expect(find.text('Accept invitation'), findsOneComponent);
      expect(find.textContaining('Sign in with'), findsNothing);
      // The screen no longer sends anyone to the CLI for this case, because
      // the case now works in the browser.
      expect(find.textContaining('zonai db admin add'), findsNothing);
    });

    testComponents('asks for no password when the table has none to set', (tester) async {
      // OTP and magic-link admin tables have no password column. A form that
      // asked for one would be collecting a value with nowhere to go, and the
      // runtime refuses a password sent to such a table outright.
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const [AuthType.otp, AuthType.magicLink]),
            onSelectProvider: (_) {},
            onAccept: _ignoreAccept,
          ),
          authTypes: const [AuthType.otp, AuthType.magicLink],
        ),
      );

      expect(find.text('Choose a password'), findsNothing);
      expect(find.text('Accept invitation'), findsOneComponent);
      expect(find.textContaining('a one-time email code or a magic link'), findsOneComponent);
    });

    testComponents('accepting hands the password to its caller', (tester) async {
      String? sent;
      var calls = 0;

      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const [AuthType.password]),
            onSelectProvider: (_) {},
            onAccept: ({String? password, Map<String, dynamic>? values}) async {
              calls++;
              sent = password;
            },
          ),
          authTypes: const [AuthType.password],
        ),
      );

      await _type(tester, 'admin-invite-password', 'correct horse battery');
      await _type(tester, 'admin-invite-password-confirm', 'correct horse battery');
      await tester.click(find.componentWithText(button, 'Accept invitation'));

      expect(calls, 1);
      expect(sent, 'correct horse battery');
    });

    testComponents('mismatched passwords are refused without a request', (tester) async {
      var calls = 0;

      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const [AuthType.password]),
            onSelectProvider: (_) {},
            onAccept: ({String? password, Map<String, dynamic>? values}) async => calls++,
          ),
          authTypes: const [AuthType.password],
        ),
      );

      await _type(tester, 'admin-invite-password', 'one thing');
      await _type(tester, 'admin-invite-password-confirm', 'another thing');
      await tester.click(find.componentWithText(button, 'Accept invitation'));

      expect(calls, 0, reason: 'a local rule must not spend the token to learn it was broken');
      expect(find.textContaining('do not match'), findsOneComponent);
    });

    testComponents('asks for the columns the account cannot be created without', (tester) async {
      // Without this the screen collects a password, posts it, and the insert
      // fails on a non-nullable column -- which is what it did before the
      // probe started reporting `fields`.
      var sent = <String, dynamic>{};

      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const [AuthType.password], fields: [_requiredText('name')]),
            onSelectProvider: (_) {},
            onAccept: ({String? password, Map<String, dynamic>? values}) async {
              sent = values ?? {};
            },
          ),
          authTypes: const [AuthType.password],
        ),
      );

      expect(find.text('name'), findsOneComponent);

      await _type(tester, 'admin-invite-field-name', 'Grace Hopper');
      await _type(tester, 'admin-invite-password', 'pw-1');
      await _type(tester, 'admin-invite-password-confirm', 'pw-1');
      await tester.click(find.componentWithText(button, 'Accept invitation'));

      expect(sent, {'name': 'Grace Hopper'});
    });

    testComponents('a required column left blank is refused without a request', (tester) async {
      var calls = 0;

      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const [AuthType.password], fields: [_requiredText('name')]),
            onSelectProvider: (_) {},
            onAccept: ({String? password, Map<String, dynamic>? values}) async => calls++,
          ),
          authTypes: const [AuthType.password],
        ),
      );

      await _type(tester, 'admin-invite-password', 'pw-1');
      await _type(tester, 'admin-invite-password-confirm', 'pw-1');
      await tester.click(find.componentWithText(button, 'Accept invitation'));

      expect(calls, 0, reason: 'a blank required column must not spend the token');
      expect(find.textContaining('name is required'), findsOneComponent);
    });

    testComponents("a refusal is shown, in the server's own words", (tester) async {
      // Not paraphrased into a house sentence. The runtime's refusals here
      // name the thing to do about them -- which provider route to use, that
      // a password is required -- and that is the actionable half.
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const [AuthType.otp]),
            onSelectProvider: (_) {},
            onAccept: ({String? password, Map<String, dynamic>? values}) async {
              throw StateError('Admin table "staff" has no password sign-in configured');
            },
          ),
          authTypes: const [AuthType.otp],
        ),
      );

      await tester.click(find.componentWithText(button, 'Accept invitation'));

      expect(find.textContaining('has no password sign-in configured'), findsOneComponent);
    });

    testComponents('a table that also allows OAuth still gets its buttons', (tester) async {
      // The invite belongs to the table, and this table's OAuth half can
      // accept it -- so the page leads with what works and is honest about
      // the rest rather than refusing outright.
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const [AuthType.password, AuthType.oauth]),
            onSelectProvider: (_) {},
            onAccept: _ignoreAccept,
          ),
          authTypes: const [AuthType.password, AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
        ),
      );

      expect(find.text('Sign in with Google'), findsOneComponent);
      expect(find.text('Choose a password'), findsOneComponent);
      expect(find.textContaining('Or accept with a provider'), findsOneComponent);
    });

    testComponents('the methods come from the probe, not from the union across every admin table', (tester) async {
      // `supportedAuthTypesProvider` is `adminSupportedAuthTypes()` -- the
      // union across EVERY `AsAdmin` table. The probe names the one table
      // this invite is actually for. A project with a Google-only admin table
      // and a password-only one must not be told its password invite can be
      // accepted with a provider button.
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const [AuthType.password]),
            onSelectProvider: (_) {},
            onAccept: _ignoreAccept,
          ),
          authTypes: const [AuthType.password, AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
        ),
      );

      expect(find.textContaining('Sign in with'), findsNothing);
      expect(find.text('Choose a password'), findsOneComponent);
    });
  });

  group('a link that cannot be accepted', () {
    testComponents('a missing token gets an explanation and no way to guess further', (tester) async {
      tester.pumpComponent(
        _scoped(
          child: const AdminInviteAcceptView(token: null, onSelectProvider: _ignore, onAccept: _ignoreAccept),
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

    testComponents('a blank token is a missing one, and is never asked about', (tester) async {
      // Not merely cosmetic: a blank token has nothing to look up, and asking
      // anyway would spend a request from the shared invite-acceptance
      // rate-limit bucket on every truncated copy-paste.
      var asked = 0;
      tester.pumpComponent(
        _scoped(
          child: const AdminInviteAcceptScreen(),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
          probe: (_) async {
            asked++;
            return const AdminInviteUnusable();
          },
        ),
      );
      await pumpEventQueue();

      expect(find.text('This invite link is not complete'), findsOneComponent);
      expect(asked, 0);
    }, url: '/_/admin/invite?token=%20%20');

    testComponents('an app with no auth methods says so instead of offering nothing', (tester) async {
      tester.pumpComponent(
        _scoped(
          child: AdminInviteAcceptView(
            token: 'invite-token',
            status: _live(const []),
            onSelectProvider: (_) {},
            onAccept: _ignoreAccept,
          ),
          authTypes: const [],
        ),
      );

      expect(find.text('Invites cannot be accepted yet'), findsOneComponent);
    });
  });

  // ---------------------------------------------------------------------
  // Design §7: the gap this screen used to have. Every test below fails if
  // the liveness probe is removed -- without it there is no `status`, the
  // view falls through to the accept path, and a dead link's first
  // impression is `/auth/admin/invite/oauth/start/:provider`'s raw 401.
  // ---------------------------------------------------------------------

  group('a token the server will not accept', () {
    testComponents('the WIRED screen explains it here rather than navigating away', (tester) async {
      // The one that matters. The probe refuses; the screen must render its
      // own words. If it instead rendered the provider buttons, the next
      // click is a full-page assign to the start route -- which is precisely
      // the raw 401 this leaf exists to replace.
      tester.pumpComponent(
        _scoped(
          child: const AdminInviteAcceptScreen(),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
          probe: (_) async => const AdminInviteUnusable(),
        ),
      );
      await pumpEventQueue();

      expect(find.text('This invite link can no longer be used'), findsOneComponent);
      expect(find.textContaining('Sign in with'), findsNothing);
      expect(find.text('Accept your invite'), findsNothing);
    }, url: '/_/admin/invite?token=tok_stale');

    testComponents('it does not say WHICH reason, because the server does not', (tester) async {
      // The oracle rule, as copy. "Expired" and "no such invite" are one
      // answer on the wire; a screen that guessed between them would put the
      // distinction back that the endpoint went to trouble to remove.
      tester.pumpComponent(
        _scoped(
          child: const AdminInviteAcceptView(token: 'tok_stale', status: AdminInviteUnusable(), onSelectProvider: _ignore, onAccept: _ignoreAccept),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
        ),
      );

      // The reasons are named together, as possibilities, and never picked
      // between: no "this invite expired", no "no invite exists".
      expect(find.textContaining('once they expire, or if whoever sent it has withdrawn it'), findsOneComponent);
      expect(find.textContaining('no such invite'), findsNothing);
      expect(find.textContaining('does not exist'), findsNothing);
    });

    testComponents('nothing is offered while the answer is still outstanding', (tester) async {
      // Including during SSR, which does not probe at all. A checking state
      // that showed the buttons would make the whole probe decorative:
      // someone with a dead link would click through before it came back.
      tester.pumpComponent(
        _scoped(
          child: const AdminInviteAcceptView(token: 'tok_pending', onSelectProvider: _ignore, onAccept: _ignoreAccept),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
        ),
      );

      expect(find.text('Checking your invitation'), findsOneComponent);
      expect(find.textContaining('Sign in with'), findsNothing);
    });

    testComponents('a server render offers nothing and asks nothing', (tester) async {
      // `isClient: false` is SSR. The probe needs a session-less round trip
      // the server render has no business making, and a render that guessed
      // "live" would paint buttons the client then has to take away.
      var asked = 0;
      tester.pumpComponent(
        _scoped(
          child: const AdminInviteAcceptScreen(),
          authTypes: const [AuthType.oauth],
          providers: [_provider(id: 'google', displayName: 'Google', kind: OAuthProviderKind.google)],
          probe: (_) async {
            asked++;
            return _live(const [AuthType.oauth]);
          },
        ),
      );
      await pumpEventQueue();

      expect(asked, 0);
      expect(find.text('Checking your invitation'), findsOneComponent);
      expect(find.textContaining('Sign in with'), findsNothing);
    }, url: '/_/admin/invite?token=tok_ssr', isClient: false);
  });

  group('the probe response', () {
    test('a live invite carries its table and the methods that table declares', () {
      final status = parseAdminInviteStatus(const {
        'live': true,
        'table': 'staff',
        'authTypes': ['oauth', 'password'],
      });

      expect(status, isA<AdminInviteLive>());
      expect((status as AdminInviteLive).table, 'staff');
      expect(status.authTypes, [AuthType.oauth, AuthType.password]);
    });

    test('every unusable answer parses to the same thing, with no reason attached', () {
      // The server sends one body for expired, revoked, spent and unknown
      // alike (`AuthHandler.kAdminInviteUnusableBody`). There is deliberately
      // no field on `AdminInviteUnusable` for a reason to arrive in, so a
      // future server that started sending one could not leak it through
      // here without someone adding the field on purpose.
      expect(parseAdminInviteStatus(const {'live': false}), isA<AdminInviteUnusable>());
      expect(parseAdminInviteStatus(const {}), isA<AdminInviteUnusable>());
      expect(parseAdminInviteStatus(const {'live': false, 'reason': 'expired'}), isA<AdminInviteUnusable>());
    });

    test('fails closed on anything ambiguous', () {
      // The accept path creates an admin account. A truncated or unexpected
      // response must not open it.
      expect(parseAdminInviteStatus(const {'live': 'true'}), isA<AdminInviteUnusable>());
      expect(parseAdminInviteStatus(const {'live': true}), isA<AdminInviteUnusable>());
      expect(parseAdminInviteStatus(const {'live': true, 'table': ''}), isA<AdminInviteUnusable>());
      expect(parseAdminInviteStatus(const {'live': true, 'table': 42}), isA<AdminInviteUnusable>());
    });

    test('an unrecognised auth type is skipped, not thrown on', () {
      // A newer server growing a fifth `AuthType` must degrade to "the
      // methods we understand", not to an error page on a good link.
      final status = parseAdminInviteStatus(const {
        'live': true,
        'table': 'staff',
        'authTypes': ['oauth', 'telepathy'],
      });

      expect((status as AdminInviteLive).authTypes, [AuthType.oauth]);
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
