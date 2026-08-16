import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../support/oauth_stub_server.dart';
import '../support/temp_directory.dart';

/// End-to-end proof for `docs/admin-invite-design.md`'s runtime leaf --
/// `inviteAdmin`/`revokeAdminInvite`/`listAdminInvites`, invite-bound OAuth
/// provisioning, and admin-removal's last-admin/self-removal/session-
/// revocation guards (§4 items 1-7 this leaf owns).
///
/// Reuses the *existing* `e2e/oauth` fixture (`UserTable extends
/// AuthTable<User> with PasswordAuth, OAuth, AsAdmin`) rather than a new
/// top-level fixture project -- `e2e/admin_invite/**` belongs to the
/// `admin-invite-e2e` leaf (design §5 W2), and a second crawler writing
/// into the same `e2e/` directory would collide with that leaf's own
/// fixture. Password sign-up (already exercised by
/// `admin_password_update_e2e_test.dart`) sets up admin JWTs for the
/// removal tests without needing OAuth at all.
///
/// The raw invite token is deliberately never returned by `inviteAdmin`
/// (design §4 item 8) and this fixture's `AppConfig` has no email config,
/// so `courier.send` is a silent no-op here (`Courier._send` returns early
/// when `config.email == null`) -- there is no production-supported way to
/// recover the token from a sent email in-process. `kIsCompiled` is false
/// under `dart test` (`bool.fromEnvironment` with no `--define`), so
/// `_inviteAdmin` mints the fixed dev token `'dev-admin-invite'` -- the same
/// escape hatch `_sendMagicLink`/`_sendResetPassword`/`_sendOtp` already use
/// for their own dev secrets. Because that token is a fixed string, only
/// *one* live admin-invite challenge may exist at a time across this whole
/// file (`_findLiveAdminInvite`'s exact-hash lookup has no other way to
/// disambiguate) -- the three tests that drive `startAdminInviteOAuth` run
/// first, in careful sequence, before anything else in this file mints a
/// second one.
void main() {
  group('admin invite runtime e2e', () {
    late Directory projectRoot;
    late Directory fixtureRoot;
    late Settings settings;
    late AppConfig appConfig;
    late OAuthStubServer stub;

    setUpAll(() async {
      if (!_runningOnDartVm) {
        return;
      }

      stub = await OAuthStubServer.start();

      fixtureRoot = Directory(
        p.normalize(p.join(Directory.current.path, '..', '..', 'e2e', 'oauth')),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/oauth'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_admin_invite_runtime_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(projectRoot: projectRoot, repoRoot: repoRoot);
      _rewriteStubBaseUrl(projectRoot: projectRoot, baseUrl: stub.baseUrl);

      final pubGet = await Process.run(Platform.resolvedExecutable, const [
        'pub',
        'get',
      ], workingDirectory: projectRoot.path);
      expect(pubGet.exitCode, 0, reason: '${pubGet.stderr}\n${pubGet.stdout}');

      settings = await runMergedScopedFuture(
        () async => Settings.load(projectRoot.path),
        override: {fsProvider.overrideWith(LocalFileSystem.new)},
      );
      appConfig = AppConfig(
        appName: 'Admin Invite Runtime E2E',
        passwordSecret: 'e2e-password-pepper',
        jwtSecret: 'e2e-zonai-jwt-secret',
        baseUrl: 'http://localhost:8080',
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
    });

    tearDownAll(() async {
      if (!_runningOnDartVm) {
        return;
      }
      await stub.close();
      deleteTempDirectory(projectRoot);
    });

    Future<T> withDb<T>(Future<T> Function(ZonaiDb db) body) {
      return runMergedScopedFuture(() async {
        final db = ZonaiDb();
        try {
          return await body(db);
        } finally {
          await db.dispose();
        }
      }, override: _e2eScopeOverrides(settings, appConfig: appConfig));
    }

    Future<String> signUpAdmin(
      ZonaiDb db,
      String email,
      String password,
    ) async {
      final result = await db.authenticate(
        'users',
        SignUpPasswordAuthPayload(
          email: email,
          password: password,
          object: const {'name': 'Admin'},
        ),
      );
      return result!.jwt;
    }

    // -----------------------------------------------------------------
    // §4 items 2, 3, 4: acceptance requires a verified, matching email; a
    // mismatch consumes nothing; the token is single-use. One combined,
    // strictly-ordered test -- see the file doc comment on why only one
    // live dev-token invite may exist at a time.
    // -----------------------------------------------------------------

    test('invite acceptance: wrong email and unverified email both refuse '
        'and leave the invite usable; a verified matching email provisions '
        'and consumes it; the spent token cannot be reused', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;
        final inviterEmail = 'accept-inviter-$unique@example.com';
        final inviterJwt = await signUpAdmin(db, inviterEmail, 'inviter-pw-1');
        final inviteeEmail = 'accept-invitee-$unique@example.com';

        await db.inviteAdmin(email: inviteeEmail, jwt: inviterJwt);

        // Wrong email entirely, verified.
        final wrongUrl = await db.startAdminInviteOAuth(
          inviteToken: 'dev-admin-invite',
          payload: const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final wrongState = Uri.parse(wrongUrl).queryParameters['state']!;
        await expectLater(
          db.completeOAuth(
            CompleteOAuthAuthPayload(
              state: wrongState,
              code: OAuthStubServer.code(
                sub: 'wrong-account-$unique',
                email: 'someone-else-$unique@example.com',
                emailVerified: true,
              ),
            ),
          ),
          throwsA(isA<AdminInviteEmailMismatchException>()),
        );

        // Right email, but the provider doesn't assert it verified.
        final unverifiedUrl = await db.startAdminInviteOAuth(
          inviteToken: 'dev-admin-invite',
          payload: const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final unverifiedState = Uri.parse(
          unverifiedUrl,
        ).queryParameters['state']!;
        await expectLater(
          db.completeOAuth(
            CompleteOAuthAuthPayload(
              state: unverifiedState,
              code: OAuthStubServer.code(
                sub: 'unverified-account-$unique',
                email: inviteeEmail,
                emailVerified: false,
              ),
            ),
          ),
          throwsA(isA<AdminInviteEmailMismatchException>()),
        );

        // Neither mismatch created a row or consumed the invite.
        final usersAfterMismatches = await db.list(
          'users',
          ListPayload(where: null),
        );
        expect(
          usersAfterMismatches.items.where((u) => u['email'] == inviteeEmail),
          isEmpty,
          reason:
              'a mismatched acceptance must create nothing (design §4 '
              'item 3)',
        );
        final stillPending = await db.listAdminInvites(jwt: inviterJwt);
        expect(
          stillPending.where((i) => i['email'] == inviteeEmail),
          hasLength(1),
          reason:
              'a mismatched acceptance must leave the invite usable '
              '(design §4 item 3)',
        );

        // Matching, verified email provisions and signs in.
        final matchUrl = await db.startAdminInviteOAuth(
          inviteToken: 'dev-admin-invite',
          payload: const StartOAuthAuthPayload(provider: 'stub-verified'),
        );
        final matchState = Uri.parse(matchUrl).queryParameters['state']!;
        final result = await db.completeOAuth(
          CompleteOAuthAuthPayload(
            state: matchState,
            code: OAuthStubServer.code(
              sub: 'matching-account-$unique',
              email: inviteeEmail,
              emailVerified: true,
            ),
          ),
        );
        expect(result.user['email'], inviteeEmail);
        expect(result.jwt, isNotEmpty);

        final usersAfterMatch = await db.list(
          'users',
          ListPayload(where: null),
        );
        expect(
          usersAfterMatch.items.where((u) => u['email'] == inviteeEmail),
          hasLength(1),
        );

        final pendingAfterMatch = await db.listAdminInvites(jwt: inviterJwt);
        expect(
          pendingAfterMatch.where((i) => i['email'] == inviteeEmail),
          isEmpty,
          reason: 'accepting an invite must consume it',
        );

        // The spent token is single-use (design §4 item 4): the same value
        // now names no live invite at all.
        await expectLater(
          db.startAdminInviteOAuth(
            inviteToken: 'dev-admin-invite',
            payload: const StartOAuthAuthPayload(provider: 'stub-verified'),
          ),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
      });
    });

    // -----------------------------------------------------------------
    // §4 item 5a: a revoked invite cannot be accepted.
    // -----------------------------------------------------------------

    test('a revoked invite cannot be accepted', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;
        final inviterEmail = 'revoke-inviter-$unique@example.com';
        final inviterJwt = await signUpAdmin(db, inviterEmail, 'inviter-pw-1');
        final inviteeEmail = 'revoke-invitee-$unique@example.com';

        await db.inviteAdmin(email: inviteeEmail, jwt: inviterJwt);
        await db.revokeAdminInvite(email: inviteeEmail, jwt: inviterJwt);

        expect(
          (await db.listAdminInvites(
            jwt: inviterJwt,
          )).where((i) => i['email'] == inviteeEmail),
          isEmpty,
        );

        await expectLater(
          db.startAdminInviteOAuth(
            inviteToken: 'dev-admin-invite',
            payload: const StartOAuthAuthPayload(provider: 'stub-verified'),
          ),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
      });
    });

    // -----------------------------------------------------------------
    // §4 item 5b: an expired invite cannot be accepted. Left with
    // `canConsume` still true (only the cleanup cron flips that) -- must be
    // the *last* test in this file to touch `startAdminInviteOAuth`, or a
    // later one could resolve the invite this test intentionally leaves
    // stale instead of its own.
    // -----------------------------------------------------------------

    test('an expired invite cannot be accepted', () async {
      if (!_runningOnDartVm) return;
      final unique = DateTime.now().microsecondsSinceEpoch;
      // Minted 8 (fake) days in the past, checked at the process's real
      // clock -- not a forward jump held for the whole test. A multi-day
      // `withClock` override active while a `ZonaiDb`/worker pool is
      // constructed or disposed made the pool (which tracks worker
      // liveness against real elapsed time) decide the CONFIG worker had
      // gone unresponsive and kill it, or hang entirely. Keeping ONE
      // `ZonaiDb` alive for the whole test and confining the fake clock to
      // just the minting call -- both construction and disposal happen at
      // real time -- avoids that, while still exercising the exact same
      // `expiresAt.isBefore(now)` check with a real, already-past
      // `expiresAt`.
      final mintedAt = DateTime.now().toUtc().subtract(const Duration(days: 8));

      await withDb((db) async {
        await withClock(Clock.fixed(mintedAt), () async {
          final inviterEmail = 'expire-inviter-$unique@example.com';
          final inviterJwt = await signUpAdmin(
            db,
            inviterEmail,
            'inviter-pw-1',
          );
          await db.inviteAdmin(
            email: 'expire-invitee-$unique@example.com',
            jwt: inviterJwt,
          );
        });

        // Back on the real clock, same live db/pool -- no fake-clock
        // window spans this call or the disposal `withDb` performs after.
        await expectLater(
          db.startAdminInviteOAuth(
            inviteToken: 'dev-admin-invite',
            payload: const StartOAuthAuthPayload(provider: 'stub-verified'),
          ),
          throwsA(isA<CodeExpiredException>()),
        );
      });
    });

    // -----------------------------------------------------------------
    // §4 item 1: only an admin JWT may invite / revoke / list. This
    // fixture's one auth table is entirely admin (design's own example
    // combination), so an authenticated-but-non-admin JWT can't be minted
    // to prove the table-scoping half of the check -- an unauthenticated
    // caller proves the gate exists at all.
    // -----------------------------------------------------------------

    test('inviteAdmin, revokeAdminInvite, and listAdminInvites all refuse '
        'an unauthenticated caller', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        await expectLater(
          db.inviteAdmin(email: 'nobody@example.com', jwt: 'not-a-real-jwt'),
          throwsA(isA<AuthException>()),
        );
        await expectLater(
          db.revokeAdminInvite(
            email: 'nobody@example.com',
            jwt: 'not-a-real-jwt',
          ),
          throwsA(isA<AuthException>()),
        );
        await expectLater(
          db.listAdminInvites(jwt: 'not-a-real-jwt'),
          throwsA(isA<AuthException>()),
        );
      });
    });

    test(
      'inviteAdmin refuses when an admin already exists for that email',
      () async {
        if (!_runningOnDartVm) return;
        await withDb((db) async {
          final unique = DateTime.now().microsecondsSinceEpoch;
          final email = 'exists-$unique@example.com';
          final jwt = await signUpAdmin(db, email, 'exists-pw-1');

          await expectLater(
            db.inviteAdmin(email: email, jwt: jwt),
            throwsA(isA<StateError>()),
          );
        });
      },
    );

    test('inviteAdmin rate-limits issuance and resends rather than '
        'duplicating a still-live invite', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;
        final inviterEmail = 'rl-inviter-$unique@example.com';
        final inviterJwt = await signUpAdmin(db, inviterEmail, 'inviter-pw-1');
        final inviteeEmail = 'rl-invitee-$unique@example.com';
        // Anchored to the real current time, not an arbitrary fixed date:
        // `AuthChallenge.createdAt` is always set via `DateTime.now()`
        // (see `auth_challenge_table.dart`), never the overridable `clock`
        // -- comparing it against a `clock.now()` fixed somewhere else in
        // time would make the rate-limit check's `createdAt.isAfter(...)`
        // trivially true or false regardless of the intended offset.
        final t0 = DateTime.now();

        await withClock(Clock.fixed(t0), () async {
          final first = await db.inviteAdmin(
            email: inviteeEmail,
            jwt: inviterJwt,
          );
          expect(first['isResend'], isFalse);

          await expectLater(
            db.inviteAdmin(email: inviteeEmail, jwt: inviterJwt),
            throwsA(isA<AuthRateLimitException>()),
          );
        });

        await withClock(
          Clock.fixed(t0.add(const Duration(minutes: 2))),
          () async {
            final second = await db.inviteAdmin(
              email: inviteeEmail,
              jwt: inviterJwt,
            );
            expect(second['isResend'], isTrue);
          },
        );

        final pending = await db.listAdminInvites(jwt: inviterJwt);
        expect(
          pending.where((i) => i['email'] == inviteeEmail),
          hasLength(1),
          reason:
              'a resend must not leave two pending invites for the same '
              'email',
        );
      });
    });

    // -----------------------------------------------------------------
    // §4 item 6: the last admin cannot be removed; an admin cannot remove
    // themselves. Normalizes the table down to exactly one admin first, so
    // the assertion doesn't depend on how many admins earlier tests in this
    // file happened to create.
    // -----------------------------------------------------------------

    test('the last admin cannot be removed, and an admin cannot remove '
        'themselves', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;
        final soleEmail = 'sole-admin-$unique@example.com';
        final soleJwtToken = await signUpAdmin(db, soleEmail, 'sole-pw-1');
        final soleJwt = await db.parseJwt(soleJwtToken);

        for (final admin in await db.listAdmins()) {
          final email = admin['email'] as String;
          if (email == soleEmail) continue;
          await db.removeAdmin(email: email, actingAdmin: soleJwt);
        }
        expect(await db.listAdmins(), hasLength(1));

        await expectLater(
          db.removeAdmin(email: soleEmail, actingAdmin: soleJwt),
          throwsA(isA<CannotRemoveSelfAsAdminException>()),
          reason:
              'self-removal must be refused even before the last-admin '
              'check would also refuse it',
        );

        await expectLater(
          db.removeAdmin(email: soleEmail),
          throwsA(isA<LastAdminCannotBeRemovedException>()),
          reason:
              'the last admin must be unremovable regardless of caller '
              '-- this call has no acting admin at all (the trusted CLI '
              'path)',
        );

        final secondEmail = 'second-admin-$unique@example.com';
        await signUpAdmin(db, secondEmail, 'second-pw-1');
        expect(await db.listAdmins(), hasLength(2));

        // Self-removal is refused independently of the last-admin count.
        await expectLater(
          db.removeAdmin(email: soleEmail, actingAdmin: soleJwt),
          throwsA(isA<CannotRemoveSelfAsAdminException>()),
        );

        await db.removeAdmin(email: secondEmail, actingAdmin: soleJwt);
        expect(await db.listAdmins(), hasLength(1));
      });
    });

    // -----------------------------------------------------------------
    // §4 item 7: removing an admin revokes their existing sessions.
    // -----------------------------------------------------------------

    test('removing an admin revokes their existing sessions', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;
        final keeperEmail = 'sess-keeper-$unique@example.com';
        final keeperJwtToken = await signUpAdmin(
          db,
          keeperEmail,
          'keeper-pw-1',
        );
        final keeperJwt = await db.parseJwt(keeperJwtToken);

        final targetEmail = 'sess-target-$unique@example.com';
        final targetToken = await signUpAdmin(db, targetEmail, 'target-pw-1');

        expect(await db.parseJwt(targetToken), isNotNull);

        await db.removeAdmin(email: targetEmail, actingAdmin: keeperJwt);

        await expectLater(
          db.parseJwt(targetToken),
          throwsA(isA<JwtRecordNotFoundException>()),
          reason:
              'a removed admin must not keep a working JWT until it '
              'expires (design §3.4 / §4 item 7)',
        );
      });
    });
  });
}

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

Set<ScopedRef<dynamic>> _e2eScopeOverrides(
  Settings settings, {
  AppConfig? appConfig,
}) {
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
    if (appConfig != null)
      configResolverProvider.overrideWith(
        () => ConfigResolver.fixed(appConfig),
      ),
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

const _forceWorkersEnv = {'ZONAI_FORCE_WORKERS': '1'};

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  // Matches the `e2e/oauth` fixture's own package name -- its
  // `lib/src/schemas/users.dart` imports `package:zonai_oauth_e2e/src/ids.dart`
  // by that literal name, so this copy must keep it too.
  pubspec.writeAsStringSync('''
name: zonai_oauth_e2e
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
