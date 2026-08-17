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

import '../support/temp_directory.dart';

/// `ZonaiDb.describeAdminInvite` -- the liveness probe
/// (`docs/admin-invite-design.md` §7).
///
/// **The property under test is a NEGATIVE one**, and it is why these live in
/// their own file rather than joining `admin_invite_runtime_e2e_test.dart`:
/// the probe must answer *identically* for an expired invite and for a token
/// that names nothing, because a difference between them is an oracle for
/// which addresses have invites pending. `DELETE /admin/invites/:email`
/// answers identically for the same reason.
///
/// Testing that needs an invite that is expired-but-not-revoked, which means
/// minting one under a fake clock, which leaves a challenge row with
/// `canConsume` still true (only the cleanup cron flips that). Under `dart
/// test` the dev token is the fixed string `'dev-admin-invite'` (`kIsCompiled`
/// is false, so `_inviteAdmin` takes the same escape hatch
/// `_sendMagicLink`/`_sendOtp` do), so `_findLiveAdminInvite`'s exact-hash
/// lookup cannot tell two such rows apart -- and the sibling file's own
/// expired test says the same about itself, and has to be the last thing in
/// it to touch that path. Two files means two VM isolates, two temp projects
/// and two databases (`package:test` gives each test FILE its own isolate),
/// so neither file has to reason about the other's leftovers.
///
/// Ordering *within* this file is still load-bearing and is stated at each
/// test: everything that needs a live invite runs before the one that
/// deliberately strands an expired one.
///
/// No OAuth stub server here. The probe never talks to a provider -- that is
/// the whole point of it being a probe -- so this file reuses `e2e/oauth`
/// purely for its `AsAdmin` collection and rewrites the stub base URL to a
/// URL nothing is expected to call.
void main() {
  group('admin invite liveness probe (runtime)', () {
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

      projectRoot = createCanonicalTempSync('zonai_admin_invite_probe_e2e_');
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
        appName: 'Admin Invite Probe E2E',
        passwordSecret: 'e2e-password-pepper-UVIjjOrrfaPgnBBY9JSAeTV3jaXjz1ky',
        jwtSecret: 'e2e-zonai-jwt-secret-8q4KsoOw8bJzuesZfcwzkhjSsCLsll1',
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

    // -----------------------------------------------------------------
    // The positive answer, and the two things it must NOT carry.
    // Runs first: it needs a genuinely live invite, and every later test
    // in this file either revokes one or strands an expired one.
    // -----------------------------------------------------------------

    test('a live token names its admin table and that table\'s auth types, '
        'carries neither the invited email nor the token, and does not '
        'consume the invite', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;
        final inviterEmail = 'probe-inviter-$unique@example.com';
        final inviterJwt = await signUpAdmin(db, inviterEmail, 'inviter-pw-1');
        final inviteeEmail = 'probe-invitee-$unique@example.com';

        await db.inviteAdmin(email: inviteeEmail, jwt: inviterJwt);

        final described = await db.describeAdminInvite(
          token: 'dev-admin-invite',
        );

        expect(described, isNotNull);
        expect(described!.table, 'users');
        // The fixture's `UserTable` mixes in `PasswordAuth` and `OAuth`, and
        // the probe reports what the table declares rather than what
        // acceptance happens to support -- design §3.3 is unbuilt and this
        // contract is what lets it be built on top later.
        expect(described.authTypes, contains(AuthType.oauth));
        expect(described.authTypes, contains(AuthType.password));

        // A record with no field for either, checked against its own
        // rendering rather than against the type -- so this still fails if
        // someone widens the record later.
        expect(described.toString(), isNot(contains(inviteeEmail)));
        expect(described.toString(), isNot(contains('dev-admin-invite')));

        // A probe is a read. Asking twice must not spend the invite, and the
        // invite must still be pending afterwards -- otherwise the screen
        // would burn the link it is trying to explain.
        expect(
          await db.describeAdminInvite(token: 'dev-admin-invite'),
          isNotNull,
        );
        expect(
          (await db.listAdminInvites(
            jwt: inviterJwt,
          )).where((i) => i['email'] == inviteeEmail),
          hasLength(1),
          reason: 'the probe must not consume the invite it describes',
        );

        // Leave no live invite behind for the tests below.
        await db.revokeAdminInvite(email: inviteeEmail, jwt: inviterJwt);
      });
    });

    // -----------------------------------------------------------------
    // The oracle rule, asserted as an EQUALITY between two answers rather
    // than as two separate null checks. Two `expect(..., isNull)` lines
    // would still pass if one branch started returning a different flavour
    // of nothing.
    // -----------------------------------------------------------------

    test(
      'a revoked token and an unknown token are indistinguishable',
      () async {
        if (!_runningOnDartVm) return;
        await withDb((db) async {
          final unique = DateTime.now().microsecondsSinceEpoch;
          final inviterEmail = 'probe-revoked-inviter-$unique@example.com';
          final inviterJwt = await signUpAdmin(
            db,
            inviterEmail,
            'inviter-pw-1',
          );
          final inviteeEmail = 'probe-revoked-invitee-$unique@example.com';

          await db.inviteAdmin(email: inviteeEmail, jwt: inviterJwt);
          await db.revokeAdminInvite(email: inviteeEmail, jwt: inviterJwt);

          final revoked = await db.describeAdminInvite(
            token: 'dev-admin-invite',
          );
          final unknown = await db.describeAdminInvite(
            token: 'no-such-token-$unique',
          );

          expect(revoked, unknown);
          expect(revoked, isNull);
        });
      },
    );

    test('a forged token and an empty one are indistinguishable from each '
        'other and from an unknown one', () async {
      if (!_runningOnDartVm) return;
      await withDb((db) async {
        final unique = DateTime.now().microsecondsSinceEpoch;

        final forged = await db.describeAdminInvite(token: 'a' * 64);
        final empty = await db.describeAdminInvite(token: '');
        final unknown = await db.describeAdminInvite(
          token: 'no-such-token-$unique',
        );

        expect(forged, unknown);
        expect(empty, unknown);
        expect(unknown, isNull);
      });
    });

    // -----------------------------------------------------------------
    // MUST BE LAST. Mints an invite 8 fake days in the past and leaves it
    // with `canConsume` still true, so from here on the fixed dev token
    // resolves to a stranded expired row.
    //
    // The fake clock covers only the minting call, not the ZonaiDb
    // construction or disposal: a multi-day `withClock` spanning either
    // makes the worker pool -- which tracks liveness against real elapsed
    // time -- decide the CONFIG worker has gone unresponsive. The sibling
    // file's expired test documents the same, and this is that lesson
    // reused rather than rediscovered.
    // -----------------------------------------------------------------

    test(
      'an expired token and an unknown token are indistinguishable',
      () async {
        if (!_runningOnDartVm) return;
        final unique = DateTime.now().microsecondsSinceEpoch;
        final mintedAt = DateTime.now().toUtc().subtract(
          const Duration(days: 8),
        );

        await withDb((db) async {
          await withClock(Clock.fixed(mintedAt), () async {
            final inviterEmail = 'probe-expired-inviter-$unique@example.com';
            final inviterJwt = await signUpAdmin(
              db,
              inviterEmail,
              'inviter-pw-1',
            );
            await db.inviteAdmin(
              email: 'probe-expired-invitee-$unique@example.com',
              jwt: inviterJwt,
            );
          });

          // Back on the real clock: the row is real, unrevoked, and 1 day past
          // its 7-day expiry.
          final expired = await db.describeAdminInvite(
            token: 'dev-admin-invite',
          );
          final unknown = await db.describeAdminInvite(
            token: 'no-such-token-$unique',
          );

          // The assertion this whole file exists for. Compared to each other,
          // not each to `isNull` -- the requirement is that they are the SAME
          // answer, and only an equality can fail when they stop being.
          expect(
            expired,
            unknown,
            reason:
                'design §7: an expired invite and an unknown one must be '
                'indistinguishable, or this probe becomes an oracle for '
                'which addresses have invites pending',
          );
          expect(expired, isNull);
        });
      },
    );
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
