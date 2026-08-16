import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../support/temp_directory.dart';

/// The emailed-challenge backdoor, closed.
///
/// `_sendOtp` used to read `switch (kIsCompiled) { false => '123456', ... }`,
/// and the three link flows the same way with `dev-magic-link`,
/// `dev-reset-password` and `dev-verify-email`. `kIsCompiled` asks whether the
/// binary was produced by `dart compile exe` — a fact about the *build*, not
/// about whether anyone can reach the process. Every source or VM deployment
/// therefore accepted `123456` as the OTP for any address on file: account
/// takeover by knowing an email.
///
/// It is now keyed on `ZONAI_INSECURE_TEST_MODE`, read from the environment at
/// runtime, which `zonai serve` refuses to start under.
///
/// These tests drive a real compiled project through the public `ZonaiDb` API,
/// so what is asserted is whether the fixed code *works as a credential* — not
/// whether some flag has some value.
void main() {
  group('insecure test mode (e2e)', () {
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
            'insecure_test_mode',
          ),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/insecure_test_mode'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_insecure_test_mode_e2e_');
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
      appConfig = const AppConfig(
        appName: 'Insecure Test Mode E2E',
        passwordSecret: 'insecure-test-mode-e2e-pw-Zt4Rq8mNvXcB3wKdHs6yLpJ2',
        jwtSecret: 'insecure-test-mode-e2e-jwt-Gf7YbQ5nTz9KwMr2VxHd4CsLp8Ja',
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
      }, override: _e2eScopeOverrides(settings));
    });

    tearDown(() => debugInsecureTestMode = null);

    tearDownAll(() {
      if (!_runningOnDartVm) return;
      debugInsecureTestMode = null;
      deleteTempDirectory(projectRoot);
    });

    // This test running from source is the point: before the fix, running from
    // source is exactly the condition under which `123456` was the OTP.
    test(
      'an OTP request from source does not hand out 123456',
      () async {
        if (!_runningOnDartVm) return;

        debugInsecureTestMode = null;
        expect(
          kInsecureTestMode,
          isFalse,
          reason: 'the test runner sets no ZONAI_INSECURE_TEST_MODE',
        );

        await _withDb(settings, appConfig, (db) async {
          const email = 'otp-off@example.com';

          await db.authenticate(
            'users',
            const SendOtpAuthPayload(email: email),
          );

          await expectLater(
            db.confirmAuth(
              const VerifyOtpAuthPayload(email: email, code: kInsecureTestOtp),
            ),
            throwsA(isA<InvalidOrExpiredCodeException>()),
            reason:
                'the fixed dev OTP must not redeem a real challenge — this is '
                'the account-takeover-by-email-address finding',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    // The other half: the hook must still work where it is legitimately
    // wanted, or it will simply be reintroduced by hand.
    test(
      'with the mode on, the fixed OTP redeems — and signs in',
      () async {
        if (!_runningOnDartVm) return;

        debugInsecureTestMode = true;

        await _withDb(settings, appConfig, (db) async {
          const email = 'otp-on@example.com';

          await db.authenticate(
            'users',
            const SendOtpAuthPayload(email: email),
          );

          final session = await db.confirmAuth(
            const VerifyOtpAuthPayload(email: email, code: kInsecureTestOtp),
          );

          expect(
            session,
            isNotNull,
            reason: 'the opt-in hook must still be usable when asked for',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'the same is true of the magic link',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          const offEmail = 'magic-off@example.com';
          const onEmail = 'magic-on@example.com';

          debugInsecureTestMode = null;
          await db.authenticate(
            'users',
            const SendMagicLinkAuthPayload(email: offEmail),
          );
          await expectLater(
            db.confirmAuth(
              VerifyMagicLinkAuthPayload(
                secret: _linkToken(kInsecureTestMagicLinkSecret, offEmail),
              ),
            ),
            throwsA(isA<InvalidOrExpiredCodeException>()),
            reason: 'the fixed dev magic-link secret must not redeem',
          );

          debugInsecureTestMode = true;
          await db.authenticate(
            'users',
            const SendMagicLinkAuthPayload(email: onEmail),
          );
          expect(
            await db.confirmAuth(
              VerifyMagicLinkAuthPayload(
                secret: _linkToken(kInsecureTestMagicLinkSecret, onEmail),
              ),
            ),
            isNotNull,
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'two challenges in a row do not collide, i.e. they are random',
      () async {
        if (!_runningOnDartVm) return;

        debugInsecureTestMode = null;

        await _withDb(settings, appConfig, (db) async {
          // Distinct addresses because a resend inside a minute is rate-limited.
          const first = 'random-a@example.com';
          const second = 'random-b@example.com';

          await db.authenticate(
            'users',
            const SendOtpAuthPayload(email: first),
          );
          await db.authenticate(
            'users',
            const SendOtpAuthPayload(email: second),
          );

          // A challenge issued for one address must not redeem for the other.
          // Under the old fixed value it always would have, since both were
          // literally `123456`.
          await expectLater(
            db.confirmAuth(
              const VerifyOtpAuthPayload(email: second, code: kInsecureTestOtp),
            ),
            throwsA(isA<InvalidOrExpiredCodeException>()),
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('insecureTestModeFromEnvironment', () {
    test('unset is off', () {
      expect(insecureTestModeFromEnvironment(const {}), isFalse);
    });

    test('set to anything meaningful is on', () {
      for (final value in ['1', 'true', 'yes', 'please']) {
        expect(
          insecureTestModeFromEnvironment({kInsecureTestModeVariable: value}),
          isTrue,
          reason: '"$value" should enable the mode',
        );
      }
    });

    // A deploy tool that renders every known flag, `false` included, must not
    // switch the backdoor ON by mentioning it.
    test('an explicit off value is off, not "present therefore on"', () {
      for (final value in ['', '  ', '0', 'false', 'FALSE', 'no', 'off']) {
        expect(
          insecureTestModeFromEnvironment({kInsecureTestModeVariable: value}),
          isFalse,
          reason: '"$value" must not enable the mode',
        );
      }
    });
  });
}

/// The `secret:email` pair, base64'd, exactly as `_sendMagicLink` builds it.
String _linkToken(String secret, String email) =>
    base64Encode('$secret:$email'.codeUnits);

Future<void> _withDb(
  Settings settings,
  AppConfig appConfig,
  Future<void> Function(ZonaiDb db) body,
) async {
  late ZonaiDb db;
  await runMergedScopedFuture(
    () async {
      db = ZonaiDb(configResolver: ConfigResolver.fixed(appConfig));
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
    // The challenge flows send an email. `AppConfig.email` is null here, so
    // the courier logs and returns — but it still has to exist.
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
    environment: const {'ZONAI_FORCE_WORKERS': '1'},
  );
  expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
}

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: zonai_insecure_test_mode
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
