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
import 'package:zonai_schema/src/internal/tables/auth_challenge_table.dart'
    show authChallenges;
import 'package:zonai_schema/zonai_schema.dart';

import '../support/temp_directory.dart';

/// `beforeSignUp` refusing a registration, against a real compiled project.
///
/// **Why this cannot be a unit test.** The unit tests prove two halves
/// separately: that `DbExtensions.dispatch` calls the hook, and that
/// `SignUpDeclinedException` survives its own `toString`/`tryParse`. Neither
/// exercises the seam between them. The hook runs in `db_extensions.exe`, a
/// separate process, and the only thing that crosses back on failure is
/// `MessageErrorResponse` — two `String` fields. The exception's *type* does
/// not survive that trip, and three separate places had to cooperate to give
/// it back:
///
///   * `_runSignUpGate` reparsing `MessageHandlerFailedException.cause`,
///   * `ZonaiDb._run` rethrowing rather than rewriting it into a `StateError`,
///   * the exception owning both halves of its own wire format.
///
/// Any one of those regressing turns a deliberate refusal into an internal
/// error, and every unit test in the suite still passes. This is the test that
/// fails.
///
/// The fixture declines by email domain rather than by a flag the test flips,
/// so the refusal and the ordinary sign-up are answered by the *same* compiled
/// worker in one run — a build step between the two cases would be a different
/// binary answering each question.
void main() {
  group('signup gate e2e', () {
    const declinedEmail = 'nope@blocked.test';
    const allowedEmail = 'ada@allowed.test';
    // A second allowed address, so the OTP positive control counts its own
    // challenge rather than one the password tests left behind.
    const otpAllowedEmail = 'grace@allowed.test';
    const declineReason = 'Sign-up from that domain is not accepted';

    late Directory projectRoot;
    late Settings settings;
    late AppConfig appConfig;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      var fixtureRoot = Directory(
        p.normalize(
          p.join(
            Directory.current.path,
            '..',
            '..',
            'e2e',
            'signup_gate_repro',
          ),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/signup_gate_repro'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_signup_gate_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(projectRoot: projectRoot, repoRoot: repoRoot);

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
        appName: 'Signup Gate E2E',
        passwordSecret: 'e2e-password-pepper-UVIjjOrrfaPgnBBY9JSAeTV3jaXjz1ky',
        jwtSecret: 'e2e-zonai-jwt-secret-8q4KsoOw8bJzuesZfcwzkhjSsCLsll1',
        baseUrl: 'http://localhost:8080',
      );

      await runMergedScopedFuture(() async {
        await _runZonai(projectRoot, const [
          'compile',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await _runZonai(projectRoot, const [
          'db',
          'migrate',
          'generate',
          '--name',
          'initialize',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await _runZonai(projectRoot, const [
          'db',
          'migrate',
          'apply',
          '--no-version-check',
          '--no-schema-version-check',
        ]);

        // The hook only runs if this exists — without it `_runExtension`
        // no-ops and every assertion below would pass for the wrong reason.
        expect(
          File(
            p.join(
              projectRoot.path,
              '.zonai',
              'executables',
              'db_extensions.exe',
            ),
          ).existsSync(),
          isTrue,
          reason: 'compile must produce db_extensions.exe',
        );
      }, override: _e2eScopeOverrides(settings));
    });

    tearDownAll(() {
      deleteTempDirectory(projectRoot);
    });

    Future<void> withDb(Future<void> Function(ZonaiDb db) body) async {
      late ZonaiDb db;
      await runMergedScopedFuture(
        () async {
          db = ZonaiDb();
          try {
            await body(db);
          } finally {
            await db.dispose();
          }
        },
        override: {
          ..._e2eScopeOverrides(settings, appConfig: appConfig),
          zonaiDbProvider.overrideWith(
            () =>
                () => db,
          ),
        },
      );
    }

    test(
      'a declined sign-up fails with the app\'s reason and creates no row',
      () async {
        if (!_runningOnDartVm) return;

        await withDb((db) async {
          await expectLater(
            db.authenticate(
              'users',
              const PasswordAuthPayload(
                email: declinedEmail,
                password: 'hunter22',
              ),
            ),
            throwsA(
              isA<SignUpDeclinedException>().having(
                (e) => e.reason,
                'reason',
                declineReason,
              ),
            ),
            reason:
                'the hook threw SignUpDeclinedException in db_extensions.exe; '
                'the type does not cross that boundary, so this fails as a '
                'StateError or a MessageHandlerFailedException if any of the '
                'three recovery points regressed',
          );

          // The refusal is worthless if the account exists anyway. This is
          // the half a status-code assertion cannot make.
          final rows = await db.list(
            'users',
            ListPayload(where: Eq('email', declinedEmail)),
          );
          expect(
            rows.items,
            isEmpty,
            reason:
                'beforeSignUp runs before the INSERT, so a declined '
                'address must leave nothing behind',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a sign-up the hook allows still succeeds and issues a session',
      () async {
        if (!_runningOnDartVm) return;

        await withDb((db) async {
          final auth = await db.authenticate(
            'users',
            const PasswordAuthPayload(
              email: allowedEmail,
              password: 'hunter22',
            ),
          );

          expect(auth, isNotNull);
          expect(auth!.user['email'], allowedEmail);
          expect(auth.jwt, isNotEmpty);

          final rows = await db.list(
            'users',
            ListPayload(where: Eq('email', allowedEmail)),
          );
          expect(rows.items, hasLength(1));
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    // The two flows below create the account at VERIFY time, so the gate had
    // to move to REQUEST time to mean anything. Before that change both of
    // these passed the send and refused ten minutes later, at a verify the
    // caller was never going to reach -- with the code already delivered.
    //
    // The assertion is the CHALLENGE ROW, not the exception alone. `_sendOtp`
    // runs gate -> insert challenge -> courier.send, so a challenge that does
    // not exist is the durable evidence that nothing was minted and nothing
    // was mailed. Asserting only the throw would still pass if the gate ran
    // after the insert.
    test(
      'a declined OTP sign-up is refused before the code is minted or sent',
      () async {
        if (!_runningOnDartVm) return;

        await withDb((db) async {
          await expectLater(
            db.authenticate(
              'users',
              const SendOtpAuthPayload(email: declinedEmail),
            ),
            throwsA(
              isA<SignUpDeclinedException>().having(
                (e) => e.reason,
                'reason',
                declineReason,
              ),
            ),
            reason:
                'the gate must run in _sendOtp, before the challenge insert -- '
                'not at verify, by which point the code has been emailed',
          );

          expect(
            await _challengeCount(db, declinedEmail),
            isZero,
            reason:
                'a challenge row means the OTP was minted and handed to the '
                'courier, so the refusal did not prevent the email',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a declined magic-link sign-up is refused before the link is sent',
      () async {
        if (!_runningOnDartVm) return;

        await withDb((db) async {
          await expectLater(
            db.authenticate(
              'users',
              const SendMagicLinkAuthPayload(email: declinedEmail),
            ),
            throwsA(
              isA<SignUpDeclinedException>().having(
                (e) => e.reason,
                'reason',
                declineReason,
              ),
            ),
          );

          expect(
            await _challengeCount(db, declinedEmail),
            isZero,
            reason: 'no challenge row means no link was minted or mailed',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    // The positive control for the two above. Without it, a gate that refused
    // EVERY OTP request -- or an `operation` that never resolved to signUp --
    // would leave both tests green while the feature was broken for everyone.
    test('an allowed OTP sign-up still mints its challenge', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        await db.authenticate(
          'users',
          const SendOtpAuthPayload(email: otpAllowedEmail),
        );

        expect(
          await _challengeCount(db, otpAllowedEmail),
          1,
          reason: 'the gate must not refuse an address the hook allows',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

/// Live `_auth_challenges` rows for one address.
///
/// Read off the internal table rather than inferred from whether a later
/// verify succeeds: "no code was sent" is a statement about what was WRITTEN,
/// and the insert is the last thing that happens before `courier.send`. An
/// inference-based check would pass over a row that is really there.
Future<int> _challengeCount(ZonaiDb db, String email) async {
  final raw = await db.open();
  final rows = await raw
      .select()
      .from(authChallenges)
      .where(authChallenges.target.equals(email));
  return rows.length;
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
    // Only the ALLOWED paths reach `courier.send` -- a declined sign-up
    // throws before it, which is the whole point -- so this override is what
    // lets the positive controls run at all. The fixture's AppConfig carries
    // no `email`, so `_Send` warns and returns without opening an SMTP
    // connection.
    courierProvider,
    migrateProvider,
    mutationsProvider,
    cleanUpProvider,
    executableStopProvider,
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

/// The fixture depends on `zonai_schema`, not `zonai`, so it cannot JIT-link a
/// project-linked entry. Forcing workers skips that re-exec and drives migrate
/// through the compiled worker executables instead.
const _forceWorkersEnv = {'ZONAI_FORCE_WORKERS': '1'};

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: zonai_signup_gate_repro
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaRoot)}
''');
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
