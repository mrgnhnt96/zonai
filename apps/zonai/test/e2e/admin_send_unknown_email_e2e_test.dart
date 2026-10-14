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
import '../support/zonai_cli.dart';

/// The admin OTP and magic-link sends answer the same for every address.
///
/// They used to throw `UserNotFoundAuthException` (401) for an address with
/// no admin row and send for one with a row (200). The non-admin sends and
/// the password-reset send already answer alike either way; this holds the
/// admin sends to the same rule. An unknown address gets nothing: no code,
/// no link, no row.
///
/// The one-minute resend cooldown answers alike too. A real address is
/// refused a second send inside the minute because its challenge row is that
/// young; an unknown address has no row, so the cooldown is held in memory
/// instead. Without it the second request answered `429` for a real address
/// and `200` for an unknown one.
void main() {
  group('admin send to an unknown email e2e', () {
    late Directory projectRoot;
    late Directory fixtureRoot;
    late Settings settings;
    late AppConfig appConfig;

    const table = 'admins';
    const adminEmail = 'real.admin@example.com';
    const adminPassword = 'Test1234!';
    const unknownEmail = 'nobody.at.all@example.com';

    // One more real admin per cooldown test.
    const otpCooldownAdmin = 'otp.cooldown@example.com';
    const magicLinkCooldownAdmin = 'link.cooldown@example.com';
    const resetCooldownAdmin = 'reset.cooldown@example.com';

    /// Runs [body] with a live [ZonaiDb] against the migrated fixture.
    Future<T> withDb<T>(Future<T> Function(ZonaiDb db) body) async {
      late ZonaiDb db;
      return await runMergedScopedFuture(
        () async {
          db = ZonaiDb();
          try {
            return await body(db);
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

    setUpAll(() async {
      if (!_runningOnDartVm) {
        return;
      }

      fixtureRoot = Directory(
        p.normalize(
          p.join(Directory.current.path, '..', '..', 'e2e', 'admin_send_repro'),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/admin_send_repro'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_admin_send_e2e_');
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
      // Matches the fixture's lib/src/config/app_config.dart (`fixtureKey`).
      appConfig = AppConfig(
        appName: 'Admin Send E2E',
        passwordSecret: _fixtureKey('p'),
        jwtSecret: _fixtureKey('j'),
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

      // The real admins, so the known-address sends have a row to find.
      await withDb((db) async {
        for (final email in [
          adminEmail,
          otpCooldownAdmin,
          magicLinkCooldownAdmin,
          resetCooldownAdmin,
        ]) {
          final signUp = await db.authenticate(
            table,
            SignUpPasswordAuthPayload(email: email, password: adminPassword),
          );
          expect(signUp, isNotNull, reason: 'sign-up must create $email');
        }
      });
    });

    tearDownAll(() {
      if (!_runningOnDartVm) {
        return;
      }
      deleteTempDirectory(projectRoot);
    });

    Future<List<Object?>> adminEmails(ZonaiDb db, String email) async {
      final rows = await db.list(table, ListPayload(where: Eq('email', email)));
      return [for (final row in rows.items) row['email']];
    }

    test('an OTP send answers alike for a real and an unknown admin', () async {
      if (!_runningOnDartVm) {
        return;
      }

      await withDb((db) async {
        final known = await db.authenticateAdmin(
          const SendOtpAuthPayload(email: adminEmail),
        );
        final unknown = await db.authenticateAdmin(
          const SendOtpAuthPayload(email: unknownEmail),
        );

        expect(known, isNull);
        expect(
          unknown,
          isNull,
          reason: 'an unknown address must not be told apart from a real one',
        );
        expect(await adminEmails(db, unknownEmail), isEmpty);
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'a magic-link send answers alike for a real and an unknown admin',
      () async {
        if (!_runningOnDartVm) {
          return;
        }

        await withDb((db) async {
          final known = await db.authenticateAdmin(
            const SendMagicLinkAuthPayload(email: adminEmail),
          );
          final unknown = await db.authenticateAdmin(
            const SendMagicLinkAuthPayload(email: unknownEmail),
          );

          expect(known, isNull);
          expect(
            unknown,
            isNull,
            reason: 'an unknown address must not be told apart from a real one',
          );
          expect(await adminEmails(db, unknownEmail), isEmpty);
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    // Nothing was sent, so there is no code to redeem. A verify for the
    // unknown address must fail rather than mint an admin account.
    test('an unknown address cannot verify its way into an admin', () async {
      if (!_runningOnDartVm) {
        return;
      }

      await withDb((db) async {
        await db.authenticateAdmin(
          const SendOtpAuthPayload(email: unknownEmail),
        );

        Object? failure;
        try {
          await db.confirmAuth(
            const VerifyOtpAuthPayload(email: unknownEmail, code: '000000'),
          );
        } on Object catch (e) {
          failure = e;
        }

        expect(failure, isNotNull, reason: 'no challenge exists to verify');
        expect(await adminEmails(db, unknownEmail), isEmpty);
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    // Each cooldown test uses its own real admin and unknown address, so the
    // sends in the tests above (real time, within the same minute) don't hold
    // their cooldown.
    Future<void> expectCooldownAlike({
      required String realEmail,
      required String unknownEmail,
      required Future<void> Function(ZonaiDb db, String email) send,
    }) async {
      Future<Object?> attempt(ZonaiDb db, String email) async {
        try {
          await send(db, email);
          return null;
        } on Object catch (e) {
          return e;
        }
      }

      await withDb((db) async {
        for (final email in [realEmail, unknownEmail]) {
          expect(
            await attempt(db, email),
            isNull,
            reason: 'the first send for $email answers 200',
          );
          expect(
            await attempt(db, email),
            isA<AuthRateLimitException>(),
            reason: 'a second send for $email inside the minute answers 429',
          );
        }

        // A real address's cooldown is its challenge row, stamped with the
        // wall clock. The unknown address's is in memory, on `clock`, so a
        // clock moved past the minute shows it lets go.
        final later = clock.now().add(const Duration(seconds: 61));
        expect(
          await withClock(Clock.fixed(later), () => attempt(db, unknownEmail)),
          isNull,
          reason: 'a send for $unknownEmail after the minute answers 200',
        );
        expect(await adminEmails(db, unknownEmail), isEmpty);
      });
    }

    test('an OTP resend inside the minute is refused for a real and an unknown '
        'admin alike', () async {
      if (!_runningOnDartVm) {
        return;
      }

      await expectCooldownAlike(
        realEmail: otpCooldownAdmin,
        unknownEmail: 'otp.cooldown.nobody@example.com',
        send: (db, email) =>
            db.authenticateAdmin(SendOtpAuthPayload(email: email)),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a magic-link resend inside the minute is refused for a real and an '
        'unknown admin alike', () async {
      if (!_runningOnDartVm) {
        return;
      }

      await expectCooldownAlike(
        realEmail: magicLinkCooldownAdmin,
        unknownEmail: 'link.cooldown.nobody@example.com',
        send: (db, email) =>
            db.authenticateAdmin(SendMagicLinkAuthPayload(email: email)),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'a password-reset resend inside the minute is refused for a real and an '
      'unknown address alike',
      () async {
        if (!_runningOnDartVm) {
          return;
        }

        await expectCooldownAlike(
          realEmail: resetCooldownAdmin,
          unknownEmail: 'reset.cooldown.nobody@example.com',
          send: (db, email) => db.sendResetPassword(
            table,
            ResetPasswordAuthPayload(email: email),
          ),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

/// Same as the fixture's `fixtureKey`.
String _fixtureKey(String salt) {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final start = salt.codeUnitAt(0);
  return String.fromCharCodes([
    for (var i = 0; i < 48; i++) chars.codeUnitAt((start + i * 7) % 62),
  ]);
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
    // The real admin's sends email. `AppConfig.email` is null here, so the
    // courier logs and returns, but it still has to exist.
    courierProvider,
    if (appConfig != null)
      configResolverProvider.overrideWith(
        () => ConfigResolver.fixed(appConfig),
      ),
  };
}

Future<void> _runZonai(Directory projectRoot, List<String> args) async {
  final result = await runZonaiCli(
    args,
    workingDirectory: projectRoot.path,
    environment: _forceWorkersEnv,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
}

/// The fixture project only depends on `zonai_schema`, not `zonai` itself,
/// so it can't JIT-link a project-linked entry (`package:zonai/...` isn't
/// resolvable from it). Forcing Mailman/IPC workers skips that project-linked
/// re-exec (see `maybeReexecProjectRuntime`) and drives `db migrate
/// generate`/`apply` through the already-compiled worker executables instead.
const _forceWorkersEnv = {'ZONAI_FORCE_WORKERS': '1'};

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: zonai_admin_send_repro
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
