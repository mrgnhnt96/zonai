import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../../lib/gen/server/.revali/server/server.dart' as gen_server;
import '../support/oauth_stub_server.dart';
import '../support/temp_directory.dart';

/// HTTP-layer proof for `docs/admin-invite-design.md` §3/§4, over a REAL
/// socket against the actual generated server (`apps/zonai/lib/gen/server`,
/// the same code `zonai compile`/`zonai serve` embeds) — the layer neither
/// `admin_invite_runtime_e2e_test.dart` (calls `ZonaiDb` directly, in one
/// process) nor `apps/server/test/admin_routes_test.dart` (drives
/// `AdminController` against a stub `AdminHandler`, and tests
/// `mayActOnAdminTable`/`buildMembersBody` as pure functions) can reach —
/// both say so in their own doc comments. No existing test in this repo
/// boots the generated server and drives it with `package:http` and real
/// `Authorization` headers; this file is that harness.
///
/// `gen_server.createServer` is called directly, in-process, rather than
/// shelling out to `zonai serve`: the CLI's `serve` command runs a version
/// check that crashes without a compiled `zonai` binary (`kIsCompiled` is a
/// compile-time define `dart run` never sets), and the fallback debug path
/// expects a sibling `../server` revali dev project that only exists in
/// `zonai dev`'s interactive workflow. `createServer` is what `zonai
/// serve`'s own `_startCompiled` path calls
/// (`apps/zonai/lib/src/db_mutator/revali.dart`) once compiled -- calling it
/// directly, inside the SAME `scoped_deps` scope this file's tests already
/// use for `zonai compile`/`db migrate`, binds a real `HttpServer` without
/// needing a second OS process at all. Its `Router` registers request
/// handling before `createServer` returns
/// (`handleRouterRequests(...).ignore()` in the generated `server.dart`), so
/// the returned `HttpServer` is genuinely already serving -- no polling
/// needed.
///
/// This fixture (`e2e/oauth`, one `AsAdmin` table plus the stub OAuth
/// providers already wired for it) covers invite issuance, the member list,
/// resending, the OAuth acceptance flow (matching/mismatched/unverified
/// email), revocation, and admin removal/session-revocation. The
/// authenticated-NON-admin refusal (design §4 item 1's table-scoping half)
/// is proven in the sibling file `admin_invite_http_nonadmin_e2e_test.dart`
/// against `e2e/admin_password_update_repro`, which already carries a
/// second, non-`AsAdmin` auth table -- this fixture's one auth table is
/// entirely admin and cannot mint that JWT, exactly as
/// `admin_invite_runtime_e2e_test.dart` and `admin_routes_test.dart` both
/// already document. Kept in a SEPARATE file/isolate on purpose:
/// `zonaiDbProvider`, `operationsProvider` et al. cache a module-level
/// singleton (`_db ??= ZonaiDb()` in `apps/zonai/lib/src/deps/zonai_db.dart`)
/// that a second `createServer` call in the SAME isolate would silently
/// reuse across fixtures. `package:test` gives each test FILE its own VM
/// isolate, so two files means two singleton pools, not one shared by
/// accident.
///
/// Neither fixture is modified, and neither is a new top-level `e2e/**`
/// directory — both already exist and are reused as-is, so this leaf's
/// commits do not touch `e2e/**` at all (see this leaf's brief on why:
/// `tool/ci/check_verify_exemptions.sh` fails on stale RECHECK markers for
/// push-notification probe files unrelated to this work, and only fires for
/// changes under `e2e/**`).
///
/// What this file does NOT attempt: naturally expiring an invite (a real
/// 7-day wait) or riding out the full one-minute resend window on a live
/// wall clock is impractical for an automated suite. The expiry check
/// itself is already proven, with a controlled clock, by
/// `admin_invite_runtime_e2e_test.dart`'s "an expired invite cannot be
/// accepted" test; this file's `revoked invite` test exercises the same
/// `InvalidOrExpiredCodeException` → 401 wiring over a real socket, and the
/// `rate-limited` test proves the *immediate* re-invite path (429) live,
/// which is the part that is new here. Also out of scope: the
/// `LastAdminCannotBeRemovedException` 409 the runtime leaf reaches through
/// the CLI's no-acting-admin call shape. `AdminHandler.removeMember` always
/// resolves `actingAdmin` from the caller's own bearer token
/// (`apps/server/lib/src/handlers/admin_handler.dart`), so the only way to
/// reach "exactly one admin, someone is trying to remove them" over HTTP is
/// for the sole admin to try to remove themselves — which
/// `CannotRemoveSelfAsAdminException` (403) refuses before the last-admin
/// check ever runs, exactly as the runtime leaf's own comment says. The 409
/// is real and reachable from the CLI; it is not reachable from this HTTP
/// surface at all, and a test that dressed up self-removal as "the last
/// admin" test would be misleading about which check actually fired.
void main() {
  group('admin invite HTTP e2e (e2e/oauth)', () {
    late Directory projectRoot;
    late OAuthStubServer stub;
    late _LiveServer server;
    late http.Client client;
    final unique = DateTime.now().microsecondsSinceEpoch;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      stub = await OAuthStubServer.start();

      final fixtureRoot = _resolveFixture('oauth');
      projectRoot = createCanonicalTempSync(
        'zonai_admin_invite_http_oauth_e2e_',
      );
      final repoRoot = fixtureRoot.parent.parent;
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(
        projectRoot: projectRoot,
        repoRoot: repoRoot,
        packageName: 'zonai_oauth_e2e',
      );
      _rewriteStubBaseUrl(projectRoot: projectRoot, baseUrl: stub.baseUrl);

      final pubGet = await Process.run(Platform.resolvedExecutable, const [
        'pub',
        'get',
      ], workingDirectory: projectRoot.path);
      expect(pubGet.exitCode, 0, reason: '${pubGet.stderr}\n${pubGet.stdout}');

      final settings = await runMergedScopedFuture(
        () async => Settings.load(projectRoot.path),
        override: {fsProvider.overrideWith(LocalFileSystem.new)},
      );

      await runMergedScopedFuture(() async {
        await _runZonai(projectRoot, [
          'compile',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await _runZonai(projectRoot, [
          'db',
          'migrate',
          'generate',
          '--name',
          'initialize',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await _runZonai(projectRoot, [
          'db',
          'migrate',
          'apply',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
      }, override: _e2eScopeOverrides(settings));

      server = await _LiveServer.start(settings);
      client = http.Client();
    });

    tearDownAll(() async {
      if (!_runningOnDartVm) return;
      client.close();
      await server.close();
      await stub.close();
      deleteTempDirectory(projectRoot);
    });

    // -----------------------------------------------------------------
    // brief case 2: unauthenticated caller refused on every admin route.
    // -----------------------------------------------------------------

    test('an unauthenticated caller is refused on every admin route', () async {
      if (!_runningOnDartVm) return;

      final members = await client.get(server.uri('/admin/members'));
      expect(members.statusCode, 403);

      final invite = await client.post(
        server.uri('/admin/invites'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'email': 'nobody-$unique@example.com'}),
      );
      expect(invite.statusCode, 403);

      final revoke = await client.send(
        http.Request(
          'DELETE',
          server.uri('/admin/invites/nobody-$unique@example.com'),
        ),
      );
      expect(revoke.statusCode, 403);

      final remove = await client.send(
        http.Request(
          'DELETE',
          server.uri('/admin/members/nobody-$unique@example.com'),
        ),
      );
      expect(remove.statusCode, 403);
    });

    // -----------------------------------------------------------------
    // brief "Positive" case: invite -> accept over the real OAuth stub ->
    // member list -> resend. One combined, ordered test: the accept flow
    // depends on the invite this test itself issues.
    // -----------------------------------------------------------------

    late String adminEmail;
    late String adminJwt;
    late String inviteeEmail;

    test('an admin invites, the invitee accepts through the stub provider with '
        'a verified matching email and is signed in as an admin, and the '
        'member list reflects it', () async {
      if (!_runningOnDartVm) return;

      adminEmail = 'http-admin-$unique@example.com';
      adminJwt = await _signUp(
        client,
        server,
        table: 'users',
        email: adminEmail,
        password: 'http-admin-pw-1',
        object: const {'name': 'Admin'},
      );

      inviteeEmail = 'http-invitee-$unique@example.com';
      final inviteResponse = await client.post(
        server.uri('/admin/invites'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $adminJwt',
        },
        body: jsonEncode({'email': inviteeEmail}),
      );
      expect(inviteResponse.statusCode, 200, reason: inviteResponse.body);
      final inviteBody = _asMap(inviteResponse);
      expect(inviteBody['email'], inviteeEmail);
      expect(inviteBody['table'], 'users');
      expect(inviteBody['isResend'], isFalse);
      // Design §4 item 8: the token exists only in the email.
      expect(inviteResponse.body, isNot(contains('dev-admin-invite')));

      final membersAfterInvite = await _getMembers(client, server, adminJwt);
      expect(
        (membersAfterInvite['invites']! as List)
            .cast<Map<String, dynamic>>()
            .where((i) => i['email'] == inviteeEmail),
        hasLength(1),
      );

      final accepted = await _acceptInvite(
        client,
        server,
        provider: 'stub-verified',
        inviteToken: 'dev-admin-invite',
        code: OAuthStubServer.code(
          sub: 'http-invitee-$unique',
          email: inviteeEmail,
          emailVerified: true,
        ),
      );
      expect(accepted.statusCode, HttpStatus.found);
      final inviteeJwt = accepted.headers['x-auth'];
      expect(inviteeJwt, isNotNull);
      expect(
        accepted.headers['location'],
        isNot(contains(inviteeJwt!)),
        reason: 'the session must never ride in the redirect URL',
      );

      // The new admin's own token now passes the admin gate for real.
      final asNewAdmin = await client.get(
        server.uri('/admin/members'),
        headers: {'authorization': 'Bearer $inviteeJwt'},
      );
      expect(asNewAdmin.statusCode, 200);

      final membersAfterAccept = await _getMembers(client, server, adminJwt);
      expect(
        (membersAfterAccept['admins']! as List)
            .cast<Map<String, dynamic>>()
            .map((a) => a['email']),
        contains(inviteeEmail),
      );
      expect(
        (membersAfterAccept['invites']! as List)
            .cast<Map<String, dynamic>>()
            .where((i) => i['email'] == inviteeEmail),
        isEmpty,
        reason: 'accepting an invite must consume it',
      );
    });

    // -----------------------------------------------------------------
    // brief negative case 3/4: wrong email and unverified email both
    // refuse, over the real callback route, and leave the invite usable.
    // -----------------------------------------------------------------

    test('accepting with a different verified email, or the right email '
        'unverified, both refuse over the real callback route and leave the '
        'invite usable', () async {
      if (!_runningOnDartVm) return;

      final mismatchInvitee = 'http-mismatch-$unique@example.com';
      final inviteResponse = await client.post(
        server.uri('/admin/invites'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $adminJwt',
        },
        body: jsonEncode({'email': mismatchInvitee}),
      );
      expect(inviteResponse.statusCode, 200, reason: inviteResponse.body);

      final wrongEmail = await _acceptInvite(
        client,
        server,
        provider: 'stub-verified',
        inviteToken: 'dev-admin-invite',
        code: OAuthStubServer.code(
          sub: 'http-wrong-$unique',
          email: 'someone-else-$unique@example.com',
          emailVerified: true,
        ),
      );
      expect(wrongEmail.statusCode, 403);

      final unverified = await _acceptInvite(
        client,
        server,
        provider: 'stub-verified',
        inviteToken: 'dev-admin-invite',
        code: OAuthStubServer.code(
          sub: 'http-unverified-$unique',
          email: mismatchInvitee,
          emailVerified: false,
        ),
      );
      expect(unverified.statusCode, 403);

      final members = await _getMembers(client, server, adminJwt);
      expect(
        (members['invites']! as List).cast<Map<String, dynamic>>().where(
          (i) => i['email'] == mismatchInvitee,
        ),
        hasLength(1),
        reason: 'a mismatched acceptance must leave the invite usable',
      );
      expect(
        (members['admins']! as List).cast<Map<String, dynamic>>().map(
          (a) => a['email'],
        ),
        isNot(contains(mismatchInvitee)),
      );

      // Clean up so this invite doesn't collide with the dev-token
      // single-live-invite constraint later tests in this group rely on.
      await client.send(
        http.Request('DELETE', server.uri('/admin/invites/${mismatchInvitee}'))
          ..headers['authorization'] = 'Bearer $adminJwt',
      );
    });

    // -----------------------------------------------------------------
    // brief negative case 5a: a revoked invite cannot be accepted.
    // -----------------------------------------------------------------

    test('a revoked invite cannot be accepted -- refused at the real start '
        'route, before any OAuth challenge is even minted', () async {
      if (!_runningOnDartVm) return;

      final revokedInvitee = 'http-revoked-$unique@example.com';
      final inviteResponse = await client.post(
        server.uri('/admin/invites'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $adminJwt',
        },
        body: jsonEncode({'email': revokedInvitee}),
      );
      expect(inviteResponse.statusCode, 200, reason: inviteResponse.body);

      final revoke = await client.send(
        http.Request('DELETE', server.uri('/admin/invites/${revokedInvitee}'))
          ..headers['authorization'] = 'Bearer $adminJwt',
      );
      expect(revoke.statusCode, anyOf(200, 204));

      final members = await _getMembers(client, server, adminJwt);
      expect(
        (members['invites']! as List).cast<Map<String, dynamic>>().where(
          (i) => i['email'] == revokedInvitee,
        ),
        isEmpty,
      );

      // A revoked token is refused at the START route itself --
      // `_findLiveAdminInvite` finds no live challenge to mint an OAuth
      // state against, so this never reaches the callback route at all
      // (unlike the email-mismatch cases above, where a challenge IS
      // minted and the refusal happens on the callback that resolves it).
      final attempt = await client.send(
        http.Request(
          'GET',
          server.uri('/auth/admin/invite/oauth/start/stub-verified', {
            'token': 'dev-admin-invite',
          }),
        )..followRedirects = false,
      );
      expect(attempt.statusCode, 401);
    });

    // -----------------------------------------------------------------
    // Design §7: `GET /auth/admin/invite?token=`, the liveness probe. Runs
    // here, straight after the revoked test, because that test leaves the
    // fixed dev token resolving to a REVOKED challenge and no live one --
    // which is exactly the state the first of these two needs.
    //
    // Byte-identity is asserted over a real socket, by comparing two
    // responses to each other. Not two separate "is it a 200 with
    // live:false" assertions: those would both still pass if one branch
    // grew a distinguishing field, and a distinguishing field is the
    // entire failure mode.
    //
    // What is NOT here: an EXPIRED invite. Expiring one needs a fake clock
    // at mint time, and the mint happens inside the live server's own
    // zone, which a `withClock` in this isolate does not reach -- the same
    // reason this file's doc comment already gives for leaving natural
    // expiry to `admin_invite_runtime_e2e_test.dart`.
    // `admin_invite_probe_runtime_e2e_test.dart` proves expired-vs-unknown
    // with a controlled clock at the layer that actually makes the
    // distinction, and `apps/server/test/oauth_routes_test.dart` proves
    // the HTTP body is one constant for every null the runtime returns.
    // Between them the chain is covered; this test covers the socket.
    // -----------------------------------------------------------------

    test('every token the server will not accept gets a byte-identical '
        'answer -- revoked, unknown and forged alike', () async {
      if (!_runningOnDartVm) return;

      // Revoked: the invite the previous test issued and then revoked.
      final revoked = await client.get(
        server.uri('/auth/admin/invite', {'token': 'dev-admin-invite'}),
      );
      final unknown = await client.get(
        server.uri('/auth/admin/invite', {'token': 'no-such-token-$unique'}),
      );
      final forged = await client.get(
        server.uri('/auth/admin/invite', {'token': 'a' * 64}),
      );

      expect(revoked.statusCode, 200, reason: revoked.body);

      for (final other in [unknown, forged]) {
        expect(
          other.statusCode,
          revoked.statusCode,
          reason:
              'design §7: a status that told these apart would be an '
              'oracle for which addresses have invites pending',
        );
        expect(other.bodyBytes, revoked.bodyBytes, reason: other.body);
        expect(other.headers['content-type'], revoked.headers['content-type']);
      }

      // And the shared answer says nothing about why.
      expect(_asMap(revoked)['live'], isFalse);
      expect(_asMap(revoked).keys, ['live']);
    });

    test('a live token names its admin table and that table\'s auth types, '
        'and never the invited email', () async {
      if (!_runningOnDartVm) return;

      final probeInvitee = 'http-probe-$unique@example.com';
      final invite = await client.post(
        server.uri('/admin/invites'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $adminJwt',
        },
        body: jsonEncode({'email': probeInvitee}),
      );
      expect(invite.statusCode, 200, reason: invite.body);

      // Unauthenticated on purpose: the invitee has no session, which is
      // the whole point. The token in the query string is the
      // authorization, exactly as it is for the start route.
      final probe = await client.get(
        server.uri('/auth/admin/invite', {'token': 'dev-admin-invite'}),
      );
      expect(probe.statusCode, 200, reason: probe.body);

      final body = _asMap(probe);
      expect(body['live'], isTrue);
      expect(body['table'], 'users');
      expect(body['authTypes'], containsAll(<String>['oauth', 'password']));

      // Design §4 item 8 and the §7 oracle rule, checked against the raw
      // bytes rather than against the parsed keys -- a leak added anywhere
      // in the envelope fails this.
      expect(probe.body, isNot(contains(probeInvitee)));
      expect(probe.body, isNot(contains('dev-admin-invite')));

      // A read, not a spend: the invite is still pending afterwards.
      final members = await _getMembers(client, server, adminJwt);
      expect(
        (members['invites']! as List).cast<Map<String, dynamic>>().where(
          (i) => i['email'] == probeInvitee,
        ),
        hasLength(1),
        reason: 'the probe must not consume the invite it describes',
      );

      // Leave no live invite behind: the tests below rely on the fixed dev
      // token resolving to their own.
      await client.send(
        http.Request('DELETE', server.uri('/admin/invites/$probeInvitee'))
          ..headers['authorization'] = 'Bearer $adminJwt',
      );
    });

    // -----------------------------------------------------------------
    // brief "resends rather than duplicating": the immediate re-invite is
    // rate-limited (429), live, over the real route. The eventual
    // isResend:true transition after the one-minute window is already
    // proven with a controlled clock by the runtime leaf -- riding out a
    // real minute per test run here would only re-prove the same check
    // more slowly. See the file doc comment.
    // -----------------------------------------------------------------

    test('inviting the same still-pending address again is rate-limited '
        'rather than creating a duplicate', () async {
      if (!_runningOnDartVm) return;

      final rlInvitee = 'http-rl-$unique@example.com';
      final first = await client.post(
        server.uri('/admin/invites'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $adminJwt',
        },
        body: jsonEncode({'email': rlInvitee}),
      );
      expect(first.statusCode, 200, reason: first.body);
      expect(_asMap(first)['isResend'], isFalse);

      final second = await client.post(
        server.uri('/admin/invites'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $adminJwt',
        },
        body: jsonEncode({'email': rlInvitee}),
      );
      expect(second.statusCode, 429);

      final members = await _getMembers(client, server, adminJwt);
      expect(
        (members['invites']! as List).cast<Map<String, dynamic>>().where(
          (i) => i['email'] == rlInvitee,
        ),
        hasLength(1),
        reason: 'the rejected retry must not have created a second row',
      );
    });

    // -----------------------------------------------------------------
    // brief case 7: removing an admin revokes their existing sessions --
    // asserted as a real 401 on a real authenticated request.
    // -----------------------------------------------------------------

    test('removing an admin revokes their existing sessions', () async {
      if (!_runningOnDartVm) return;

      final targetEmail = 'http-sess-target-$unique@example.com';
      final targetJwt = await _signUp(
        client,
        server,
        table: 'users',
        email: targetEmail,
        password: 'target-pw-1',
        object: const {'name': 'Target'},
      );

      final stillWorks = await client.get(
        server.uri('/admin/members'),
        headers: {'authorization': 'Bearer $targetJwt'},
      );
      expect(stillWorks.statusCode, 200);

      final remove = await client.send(
        http.Request('DELETE', server.uri('/admin/members/${targetEmail}'))
          ..headers['authorization'] = 'Bearer $adminJwt',
      );
      expect(
        remove.statusCode,
        200,
        reason: await remove.stream.bytesToString(),
      );

      final afterRemoval = await client.get(
        server.uri('/admin/members'),
        headers: {'authorization': 'Bearer $targetJwt'},
      );
      expect(
        afterRemoval.statusCode,
        401,
        reason:
            'a removed admin must not keep a working JWT until it '
            'expires (design §3.4 / §4 item 7)',
      );
    });

    // -----------------------------------------------------------------
    // brief case 6 (the half reachable over HTTP -- see the file doc
    // comment on why the 409 last-admin path is not).
    // -----------------------------------------------------------------

    test(
      'an admin cannot remove themselves, including as the sole admin',
      () async {
        if (!_runningOnDartVm) return;

        final soleEmail = 'http-sole-$unique@example.com';
        final soleJwt = await _signUp(
          client,
          server,
          table: 'users',
          email: soleEmail,
          password: 'sole-pw-1',
          object: const {'name': 'Sole'},
        );

        // Normalize down to exactly this admin, using its own bearer to
        // remove every other admin this group's earlier tests created.
        final before = await _getMembers(client, server, soleJwt);
        for (final admin
            in (before['admins']! as List).cast<Map<String, dynamic>>()) {
          final email = admin['email'] as String;
          if (email == soleEmail) continue;
          final removed = await client.send(
            http.Request('DELETE', server.uri('/admin/members/${email}'))
              ..headers['authorization'] = 'Bearer $soleJwt',
          );
          expect(removed.statusCode, 200, reason: '$email: removal failed');
        }

        final after = await _getMembers(client, server, soleJwt);
        expect(after['admins'], hasLength(1));

        final selfRemoval = await client.send(
          http.Request('DELETE', server.uri('/admin/members/${soleEmail}'))
            ..headers['authorization'] = 'Bearer $soleJwt',
        );
        expect(
          selfRemoval.statusCode,
          403,
          reason: 'self-removal must be refused even as the sole admin',
        );

        final stillThere = await client.get(
          server.uri('/admin/members'),
          headers: {'authorization': 'Bearer $soleJwt'},
        );
        expect(
          stillThere.statusCode,
          200,
          reason: 'a refused self-removal must not have revoked the caller',
        );
      },
    );

    // -----------------------------------------------------------------
    // brief case 8: the raw invite token in no response body and no log
    // line, checked against everything this group's own tests actually
    // sent and everything the live server actually logged.
    // -----------------------------------------------------------------

    test(
      'the raw invite token never reaches the server process log output',
      () async {
        if (!_runningOnDartVm) return;

        expect(
          server.capturedLogOutput,
          isNot(contains('dev-admin-invite')),
          reason:
              'design §4 item 8 -- checked against everything the live '
              'server logged across this whole group, not just this test',
        );
      },
    );

    // -----------------------------------------------------------------
    // brief case 9: the OAuth `code`, `state` and client secret in no log
    // line either (docs/oauth.md §4 item 7).
    //
    // The redaction *function* is unit-tested and the response *surfaces*
    // are asserted elsewhere; this is the end of that chain -- what the
    // process, running at `Logger(level: .verbose)`, actually wrote. A
    // redaction that is correct but never reached would pass every other
    // test in the repo and fail this one.
    // -----------------------------------------------------------------

    test('no OAuth code, state or client secret reaches the server process '
        'log output', () async {
      if (!_runningOnDartVm) return;

      final log = server.capturedLogOutput;

      // Guards the assertion against passing because the log is empty or
      // because no exchange ever happened -- both would make every
      // `isNot(contains(...))` below vacuously true.
      expect(
        log,
        isNotEmpty,
        reason:
            'nothing was logged at all -- the assertions below would be '
            'vacuous',
      );
      expect(
        _oauthSecretsOnTheWire,
        isNotEmpty,
        reason: 'no OAuth exchange was recorded -- nothing to look for',
      );

      for (final secret in _oauthSecretsOnTheWire) {
        expect(
          log,
          isNot(contains(secret)),
          // The value itself is a test-fixture code/state, so naming its
          // length rather than the value keeps the habit right for the
          // real ones.
          reason:
              'an OAuth code or state (${secret.length} chars) reached the '
              'log -- a redirect URI or a request line is being logged '
              'unredacted',
        );
      }

      // The client secret never leaves the server, so it appearing here
      // means a provider config was dumped rather than a request echoed --
      // a different bug from the two above, and a worse one.
      for (final clientSecret in const [
        'stub-client-secret',
        'stub-oidc-client-secret',
      ]) {
        expect(
          log,
          isNot(contains(clientSecret)),
          reason: '$clientSecret (e2e/oauth fixture) reached the log',
        );
      }
    });
  });
}

// ===========================================================================
// Shared HTTP helpers.
// ===========================================================================

Future<String> _signUp(
  http.Client client,
  _LiveServer server, {
  required String table,
  required String email,
  required String password,
  Map<String, Object?>? object,
}) async {
  final response = await client.post(
    server.uri('/auth/sign-up'),
    headers: const {'content-type': 'application/json'},
    body: jsonEncode({
      'table': table,
      'type': 'signUp',
      'email': email,
      'password': password,
      if (object != null) 'object': object,
    }),
  );
  expect(response.statusCode, 200, reason: '$table/$email: ${response.body}');
  return _asMap(response)['accessToken'] as String;
}

Future<Map<String, dynamic>> _getMembers(
  http.Client client,
  _LiveServer server,
  String adminJwt,
) async {
  final response = await client.get(
    server.uri('/admin/members'),
    headers: {'authorization': 'Bearer $adminJwt'},
  );
  expect(response.statusCode, 200, reason: response.body);
  return _asMap(response);
}

/// Every OAuth `code` and `state` this file actually put on the wire.
///
/// Recorded rather than re-derived: `state` is minted by the server and only
/// ever appears in a redirect `Location`, so the log assertion at the end of
/// the group has no other way to know what to look for. Accumulating across
/// the whole group means that assertion checks every exchange the file
/// performed, not just one it re-staged for itself.
final _oauthSecretsOnTheWire = <String>[];

/// Drives `GET /auth/admin/invite/oauth/start/:provider` (without following
/// its redirect) to recover `state`, then `GET /auth/oauth/callback/:provider`
/// with [code] and that `state`. Returns the callback's raw response --
/// callers read `.statusCode` and, on success, the `x-auth` header.
Future<http.Response> _acceptInvite(
  http.Client client,
  _LiveServer server, {
  required String provider,
  required String inviteToken,
  required String code,
}) async {
  final start = await client.send(
    http.Request(
      'GET',
      server.uri('/auth/admin/invite/oauth/start/$provider', {
        'token': inviteToken,
      }),
    )..followRedirects = false,
  );
  expect(
    start.statusCode,
    HttpStatus.found,
    reason: await start.stream.bytesToString(),
  );
  final location = start.headers['location'];
  expect(location, isNotNull);
  final state = Uri.parse(location!).queryParameters['state'];
  expect(state, isNotNull, reason: 'no state in $location');
  _oauthSecretsOnTheWire.addAll([code, state!]);

  final callback = await client.send(
    http.Request(
      'GET',
      server.uri('/auth/oauth/callback/$provider', {
        'code': code,
        'state': state,
      }),
    )..followRedirects = false,
  );
  return http.Response.fromStream(callback);
}

/// Revali's default response handler wraps a returned `Map` body in a
/// `{"data": ...}` envelope; this unwraps it so callers can read the
/// handler's own return shape (`{email, table, ...}`, `{admins, invites}`,
/// `{accessToken, user}`) directly.
Map<String, dynamic> _asMap(http.Response response) {
  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  return switch (decoded) {
    {'data': final Map<String, dynamic> data} => data,
    _ => decoded,
  };
}

// ===========================================================================
// A real, live server, bound in-process (see the file doc comment for why).
// ===========================================================================

class _LiveServer {
  _LiveServer._(this._httpServer, this._logBuffer);

  final HttpServer _httpServer;
  final StringBuffer _logBuffer;

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.http('127.0.0.1:${_httpServer.port}', path, query);

  String get capturedLogOutput => _logBuffer.toString();

  static Future<_LiveServer> start(Settings settings) async {
    final logBuffer = StringBuffer();
    final logController = StreamController<List<int>>();
    logController.stream.transform(utf8.decoder).listen(logBuffer.write);
    final captureSink = IOSink(logController.sink);

    // Overriding `loggerProvider` below is NOT enough to see request logging,
    // and for a long time this class quietly proved nothing because of it.
    //
    // `TraceId`'s lifecycle component re-overrides `loggerProvider` for the
    // duration of every request with `Logger.print(...)`
    // (`components/lifecycle_components/trace_id.dart`), which writes through
    // `PrintSink` -> Dart's `print`. The injected `captureSink` is discarded
    // at that point, so `capturedLogOutput` only ever held the handful of
    // startup lines emitted before the first request -- 178 bytes of config-
    // executable chatter, against which any `isNot(contains(...))` passes for
    // free.
    //
    // `print` is zone-scoped, so capturing the zone is what actually works.
    // The server's request loop is started inside `createServer` and inherits
    // this zone, so every later request logs through here. The line is still
    // forwarded to the parent zone: swallowing it would make a failing run
    // harder to read, and the buffer is for asserting on, not for hiding
    // output.
    final httpServer = await runZoned(
      () => runMergedScopedFuture(
        () => gen_server.createServer(null, const []),
        override: {
          // The four this file actually needs to control.
          argsProvider.overrideWith(
            () => Args.parse(const ['--host=127.0.0.1', '--port=0']),
          ),
          fsProvider.overrideWith(LocalFileSystem.new),
          loggerProvider.overrideWith(
            () => Logger(
              level: .verbose,
              stdout: captureSink,
              stderr: captureSink,
            ),
          ),
          settingsProvider.overrideWith(() => settings),
          // Everything else, at its production default -- mirrors
          // `apps/zonai/lib/src/bootstrap.dart`'s `runZonai` registration set,
          // since that is the only place this exact list is proven correct.
          envProvider,
          courierProvider,
          processProvider,
          cleanUpProvider,
          mutationsProvider,
          keyboardInputProvider,
          messageContractHashProvider,
          migrateProvider,
          extensionsProvider,
          executableStopProvider,
          rulesProvider,
          rateLimitsProvider,
          cronsProvider,
          rateLimiterProvider,
          configProvider,
          configResolverProvider,
          killProvider,
          stdinProvider,
          operationsProvider,
          revaliProvider,
          zonaiDbProvider,
          versionsProvider,
          schemaVersionCheckProvider,
        },
      ),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          logBuffer.writeln(line);
          parent.print(zone, line);
        },
      ),
    );

    return _LiveServer._(httpServer, logBuffer);
  }

  Future<void> close() => _httpServer.close(force: true);
}

// ===========================================================================
// Fixture plumbing -- matches the pattern every other file in this
// directory already uses (see e.g. admin_invite_runtime_e2e_test.dart).
// ===========================================================================

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

const _forceWorkersEnv = {'ZONAI_FORCE_WORKERS': '1'};

Directory _resolveFixture(String name) {
  var fixtureRoot = Directory(
    p.normalize(p.join(Directory.current.path, '..', '..', 'e2e', name)),
  );
  if (!fixtureRoot.existsSync()) {
    fixtureRoot = Directory(p.normalize('e2e/$name'));
  }
  expect(
    fixtureRoot.existsSync(),
    isTrue,
    reason: 'fixture missing at ${fixtureRoot.path}',
  );
  return fixtureRoot;
}

Set<ScopedRef<dynamic>> _e2eScopeOverrides(Settings settings) {
  return {
    fsProvider.overrideWith(LocalFileSystem.new),
    loggerProvider.overrideWith(() => Logger(level: .error)),
    settingsProvider.overrideWith(() => settings),
    processProvider,
    migrateProvider,
    mutationsProvider,
    cleanUpProvider,
    executableStopProvider,
    courierProvider,
  };
}

Future<void> _runZonai(Directory projectRoot, List<String> args) async {
  final zonaiEntry = p.normalize(
    p.join(Directory.current.path, 'bin', 'zonai.dart'),
  );
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['run', zonaiEntry, ...args],
    workingDirectory: projectRoot.path,
    environment: _forceWorkersEnv,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
}

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
  required String packageName,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: $packageName
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaRoot)}
''');
}

void _rewriteStubBaseUrl({
  required Directory projectRoot,
  required String baseUrl,
}) {
  final usersSchema = File(
    p.join(projectRoot.path, 'lib', 'src', 'schemas', 'users.dart'),
  );
  final rewritten = usersSchema.readAsStringSync().replaceAll(
    '__OAUTH_STUB_BASE_URL__',
    baseUrl,
  );
  expect(
    rewritten,
    isNot(contains('__OAUTH_STUB_BASE_URL__')),
    reason: 'stub base URL placeholder was not found in users.dart',
  );
  usersSchema.writeAsStringSync(rewritten);
}

void _copyTree(Directory source, Directory destination) {
  for (final entity in source.listSync(recursive: true)) {
    final relative = p.relative(entity.path, from: source.path);
    if (relative.startsWith('.zonai') || relative == '.dart_tool') {
      continue;
    }
    final targetPath = p.join(destination.path, relative);
    if (entity is Directory) {
      Directory(targetPath).createSync(recursive: true);
    } else if (entity is File) {
      Directory(p.dirname(targetPath)).createSync(recursive: true);
      entity.copySync(targetPath);
    }
  }
}
