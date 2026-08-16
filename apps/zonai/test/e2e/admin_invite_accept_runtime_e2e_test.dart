import 'dart:convert';
import 'dart:io';

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

import '../support/temp_directory.dart';

/// `ZonaiDb.acceptAdminInvite` -- direct acceptance
/// (`docs/admin-invite-design.md` §3.3).
///
/// The half of acceptance that does not go through a provider: an admin table
/// signing in with a password, an OTP or a magic link. `e2e/oauth`'s
/// `UserTable` is `with PasswordAuth, OAuth, AsAdmin`, so it exercises both
/// the password branch and the "OAuth is present but not the only option"
/// case in one fixture. The OAuth-*only* refusal needs a table with no other
/// method and lives with the fixture that has one, in
/// `oauth_admin_add_e2e_test.dart`.
///
/// Its own file rather than joining `admin_invite_probe_runtime_e2e_test.dart`
/// for the reason that file states about itself: under `dart test` the invite
/// token is the fixed string `'dev-admin-invite'` (`kIsCompiled` is false, so
/// `_issueAdminInvite` takes the same escape hatch `_sendMagicLink`/`_sendOtp`
/// do), so `_findLiveAdminInvite`'s exact-hash lookup cannot tell two pending
/// invites apart. `package:test` gives each test FILE its own isolate, temp
/// project and database, so neither file has to reason about the other's
/// leftovers.
///
/// **Ordering within this file is load-bearing** and is stated at each test.
/// Every test that needs a live invite mints its own first; the one that
/// deliberately spends a token runs after the ones that must find it unspent.
///
/// No OAuth stub server. Nothing here talks to a provider -- that is what
/// makes it §3.3 -- so the stub base URL is rewritten to one nothing is
/// expected to call.
void main() {
  group('admin invite direct acceptance (runtime)', () {
    late Directory projectRoot;
    late Settings settings;
    late AppConfig appConfig;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      var fixtureRoot = Directory(
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

      projectRoot = createCanonicalTempSync('zonai_admin_invite_accept_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(projectRoot: projectRoot, repoRoot: repoRoot);
      _rewriteStubBaseUrl(
        projectRoot: projectRoot,
        baseUrl: 'http://127.0.0.1:1',
      );

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
        appName: 'Admin Invite Accept E2E',
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
      if (!_runningOnDartVm) return;
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

    /// The invite token every test here mints and spends. Fixed under
    /// `dart test`, which is why each test mints its own invite immediately
    /// before using it rather than relying on one from a previous test.
    const inviteToken = 'dev-admin-invite';

    /// Signs up an admin, then invites [invitee]. Returns the inviter's JWT
    /// so the caller can check the pending list afterwards.
    Future<String> inviteFrom(
      ZonaiDb db,
      String inviter,
      String invitee,
    ) async {
      final jwt = await signUpAdmin(db, inviter, 'inviter-pw-1');
      await db.inviteAdmin(email: invitee, jwt: jwt);
      return jwt;
    }

    // -----------------------------------------------------------------
    // The happy path, and what it must leave behind. Runs first: it needs a
    // live invite, and it is the test that legitimately spends one.
    // -----------------------------------------------------------------

    test('accepting with a password creates the admin, consumes the invite '
        'and returns a working session', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;
        final inviteeEmail = 'accept-invitee-$unique@example.com';
        final inviterJwt = await inviteFrom(
          db,
          'accept-inviter-$unique@example.com',
          inviteeEmail,
        );

        final result = await db.acceptAdminInvite(
          token: inviteToken,
          password: 'invitee-pw-1',
          // `e2e/oauth`'s `User.name` is non-nullable, so acceptance needs it
          // exactly as `zonai db admin add --data` does. The probe reports
          // this column as a `field` so the screen can ask for it.
          object: const {'name': 'Invited Admin'},
        );

        // A session, not just a row. The acceptance IS the first sign-in --
        // a flow that created the account and then asked the invitee to log
        // in would be asking them to prove what they just proved.
        expect(result.jwt, isNotEmpty);

        // The row is in the invite's own table, at the invited address --
        // which the request never got to state.
        final admins = await db.listAdmins();
        expect(
          admins.where((a) => a['email'] == inviteeEmail),
          hasLength(1),
          reason: 'acceptance must create the admin row it signs in as',
        );

        // Design §4 item 4: single use. The invite is gone from the pending
        // list, and the token no longer names anything live.
        expect(
          (await db.listAdminInvites(
            jwt: inviterJwt,
          )).where((i) => i['email'] == inviteeEmail),
          isEmpty,
          reason: 'an accepted invite must not stay pending',
        );
        expect(await db.describeAdminInvite(token: inviteToken), isNull);
      });
    });

    test('the account it created can sign in on its own afterwards', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;
        final inviteeEmail = 'accept-signin-$unique@example.com';
        await inviteFrom(
          db,
          'accept-signin-inv-$unique@example.com',
          inviteeEmail,
        );

        await db.acceptAdminInvite(
          token: inviteToken,
          password: 'invitee-pw-2',
          object: const {'name': 'Invited Admin'},
        );

        // The password the invitee chose is the one the account has. Without
        // this, "accepted" could mean a row with no usable credential on it
        // and nobody would notice until the next visit.
        final signedIn = await db.authenticate(
          'users',
          SignInPasswordAuthPayload(
            email: inviteeEmail,
            password: 'invitee-pw-2',
          ),
        );
        expect(signedIn, isNotNull);
        expect(signedIn!.jwt, isNotEmpty);
      });
    });

    // -----------------------------------------------------------------
    // Refusals. Each one must leave the invite usable (design §4 item 3),
    // so each mints its own and checks it afterwards.
    // -----------------------------------------------------------------

    test('a missing password is refused, and the invite survives it', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;
        final inviteeEmail = 'accept-nopw-$unique@example.com';
        final inviterJwt = await inviteFrom(
          db,
          'accept-nopw-inv-$unique@example.com',
          inviteeEmail,
        );

        await expectLater(
          db.acceptAdminInvite(token: inviteToken),
          throwsA(isA<AdminInvitePasswordMismatchException>()),
        );

        // The whole point of refusing before consuming: someone who submits
        // the form wrong gets to try again instead of needing a fresh invite.
        expect(
          (await db.listAdminInvites(
            jwt: inviterJwt,
          )).where((i) => i['email'] == inviteeEmail),
          hasLength(1),
          reason: 'a refused acceptance must not spend the invite',
        );
        expect(
          (await db.listAdmins()).where((a) => a['email'] == inviteeEmail),
          isEmpty,
          reason: 'a refused acceptance must create nothing',
        );

        // Leave nothing pending. Under `dart test` the token is the fixed
        // string `'dev-admin-invite'`, so an invite this test deliberately
        // kept alive is indistinguishable from the next test's -- and
        // `_findLiveAdminInvite` would answer with whichever the database
        // returned first.
        await db.revokeAdminInvite(email: inviteeEmail, jwt: inviterJwt);
      });
    });

    test('an unknown token is refused and creates nothing', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final before = (await db.listAdmins()).length;

        await expectLater(
          db.acceptAdminInvite(
            token: 'not-a-real-invite-token',
            password: 'whatever-pw-1',
            object: const {'name': 'Invited Admin'},
          ),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );

        expect(await db.listAdmins(), hasLength(before));
      });
    });

    test('a revoked invite cannot be accepted', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;
        final inviteeEmail = 'accept-revoked-$unique@example.com';
        final inviterJwt = await inviteFrom(
          db,
          'accept-revoked-inv-$unique@example.com',
          inviteeEmail,
        );

        await db.revokeAdminInvite(email: inviteeEmail, jwt: inviterJwt);

        // Design §4 item 5. Revoke is what an admin does about an invite sent
        // to the wrong address, so it has to beat the link that is already in
        // that inbox.
        await expectLater(
          db.acceptAdminInvite(
            token: inviteToken,
            password: 'revoked-pw-1',
            object: const {'name': 'Invited Admin'},
          ),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
        expect(
          (await db.listAdmins()).where((a) => a['email'] == inviteeEmail),
          isEmpty,
        );
      });
    });

    // -----------------------------------------------------------------
    // Runs last: it spends a token, and the tests above need theirs unspent.
    // -----------------------------------------------------------------

    test('the same token cannot be accepted twice', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;
        final inviteeEmail = 'accept-twice-$unique@example.com';
        await inviteFrom(
          db,
          'accept-twice-inv-$unique@example.com',
          inviteeEmail,
        );

        await db.acceptAdminInvite(
          token: inviteToken,
          password: 'twice-pw-1',
          object: const {'name': 'Invited Admin'},
        );

        // Not merely "the second call fails" -- the second call must fail
        // *without* a second admin row, which is the thing a replayed link
        // would otherwise create.
        await expectLater(
          db.acceptAdminInvite(
            token: inviteToken,
            password: 'twice-pw-2',
            object: const {'name': 'Invited Admin'},
          ),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
        expect(
          (await db.listAdmins()).where((a) => a['email'] == inviteeEmail),
          hasLength(1),
        );
      });
    });
  });
}

// ===========================================================================
// Fixture plumbing -- the same shape every other file in this directory uses.
// ===========================================================================

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

const _forceWorkersEnv = {'ZONAI_FORCE_WORKERS': '1'};

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
