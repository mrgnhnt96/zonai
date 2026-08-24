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
import 'package:zonai_schema/src/internal/tables/password_reset_requirement_table.dart'
    show PasswordResetReason;
import 'package:zonai_schema/zonai_schema.dart';
import '../support/temp_directory.dart';

/// The forced-password-reset control, against a COMPILED project.
///
/// This file exists because of a boundary, not because a second layer of the
/// same tests is nice to have. `requirePasswordReset` resolves an account by
/// email through `_authRecord` → `ViewAuthOperationRequest`, and reads two
/// column names through `GetColumnNameRequest`. All three need a compiled
/// operations worker, which the bare `db_mutator` test harness does not have
/// -- the same boundary `password_reset_requirement_test.dart` and
/// `api_token_resolution_test.dart` already state for themselves. So
/// everything below is asserted HERE or it is asserted nowhere:
///
///   * setting a requirement REVOKES the account's live sessions. This is the
///     load-bearing half of the whole control: without it the requirement
///     binds only sign-ins that have not happened yet, and whoever the
///     password leaked to keeps their session for the rest of `jwtExpiresIn`
///     (14 days by default) while the owner believes they were just locked
///     out.
///   * the gate hands back a one-time ticket and mints NO session.
///   * confirming with that ticket clears the requirement, and the ticket
///     does not work twice.
///   * submitting the CURRENT password answers reuse and does NOT burn the
///     ticket -- a typo must not cost the recovery path.
///   * an EMAILED reset also clears a forced requirement (the demand was
///     "choose a new password", never "choose it this particular way").
///   * OTP still signs in, and the requirement SURVIVES that sign-in.
///   * an OAuth-only collection refuses a requirement outright.
///
/// What this does NOT cover: the HTTP status and body. That is
/// `apps/server/test/password_reset_required_envelope_test.dart` for the
/// mapping and `tool/ci/e2e/drive.dart` for the wire.
void main() {
  group('forced password reset e2e', () {
    late Directory projectRoot;
    late Directory fixtureRoot;
    late Settings settings;
    late AppConfig appConfig;

    setUpAll(() async {
      if (!_runningOnDartVm) {
        return;
      }

      fixtureRoot = Directory(
        p.normalize(
          p.join(
            Directory.current.path,
            '..',
            '..',
            'e2e',
            'forced_password_reset',
          ),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/forced_password_reset'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_forced_password_reset_e2e_');
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
        appName: 'Forced Password Reset E2E',
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

        final operationsExe = File(
          p.join(
            projectRoot.path,
            '.zonai',
            'executables',
            'db_operations.exe',
          ),
        );
        expect(
          operationsExe.existsSync(),
          isTrue,
          reason:
              'compile must produce db_operations.exe -- it is the worker '
              'this whole file exists to have',
        );
      }, override: _e2eScopeOverrides(settings));
    });

    tearDown(() {
      // Never left set. It makes every emailed secret and every OTP a fixed,
      // publicly-known value, so a test that forgets to clear it hands the
      // next one a backdoor and a false pass.
      debugInsecureTestMode = null;
    });

    tearDownAll(() {
      deleteTempDirectory(projectRoot);
    });

    /// Everything runs against one compiled project, so every test owns its
    /// own address. Sharing one would let a requirement written by an earlier
    /// test satisfy a later one.
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

    test('setting a requirement revokes the sessions the account already '
        'holds', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        const email = 'revoked@example.com';
        const password = 'old-password-revoked-1';

        final signUp = await db.authenticate(
          'admins',
          const PasswordAuthPayload(email: email, password: password),
        );
        expect(signUp, isNotNull);
        final token = signUp!.jwt;

        // The control: the session works right now, so its later failure is
        // caused by the requirement rather than by never having been valid.
        expect(await db.parseJwt(token), isNotNull);

        await db.requirePasswordReset(
          table: 'admins',
          email: email,
          reason: PasswordResetReason.compromised,
          byUserId: 'cli',
        );

        await expectLater(
          db.parseJwt(token),
          throwsA(isA<JwtRecordNotFoundException>()),
          reason:
              'THE load-bearing half. A requirement that only gates future '
              'sign-ins leaves a leaked password\'s existing session live for '
              'the rest of jwtExpiresIn.',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'a gated sign-in mints no session and hands back a ticket',
      () async {
        if (!_runningOnDartVm) return;

        await withDb((db) async {
          const email = 'gated@example.com';
          const password = 'old-password-gated-1';

          await db.authenticate(
            'admins',
            const PasswordAuthPayload(email: email, password: password),
          );
          await db.requirePasswordReset(
            table: 'admins',
            email: email,
            reason: PasswordResetReason.temporaryPassword,
            byUserId: 'cli',
          );

          final refusal = await _captureRefusal(
            () => db.authenticate(
              'admins',
              const SignInPasswordAuthPayload(email: email, password: password),
            ),
          );

          expect(refusal.reason, PasswordResetReason.temporaryPassword);
          expect(refusal.expiresIn, const Duration(minutes: 15));
          expect(
            utf8.decode(base64Decode(refusal.token)).split(':').last,
            email,
            reason:
                'the ticket is `base64(<secret>:<email>)` -- the same shape the '
                'emailed link carries, which is why POST /auth/confirm resolves '
                'it with no new code',
          );
          expect(
            '$refusal',
            isNot(contains(refusal.token)),
            reason:
                'toString() must never carry the ticket: the catcher logs the '
                'exception server-side, and a one-time credential in the log '
                'table outlives the 15 minutes it is good for',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('the ticket completes the reset, clears the requirement, and does '
        'not work twice', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        const email = 'roundtrip@example.com';
        const password = 'old-password-roundtrip-1';
        const newPassword = 'new-password-roundtrip-2';

        final signUp = await db.authenticate(
          'admins',
          const PasswordAuthPayload(email: email, password: password),
        );
        final userId = signUp!.user['id']! as String;

        await db.requirePasswordReset(
          table: 'admins',
          email: email,
          reason: PasswordResetReason.adminForced,
          byUserId: 'cli',
        );
        expect(
          await db.passwordResetRequirement(table: 'admins', userId: userId),
          isNotNull,
        );

        final refusal = await _captureRefusal(
          () => db.authenticate(
            'admins',
            const SignInPasswordAuthPayload(email: email, password: password),
          ),
        );

        await db.confirmAuth(
          ConfirmResetPasswordAuthPayload(
            token: refusal.token,
            newPassword: newPassword,
          ),
        );

        expect(
          await db.passwordResetRequirement(table: 'admins', userId: userId),
          isNull,
          reason: 'the requirement is satisfied by the password CHANGING',
        );

        final signedIn = await db.authenticate(
          'admins',
          const SignInPasswordAuthPayload(email: email, password: newPassword),
        );
        expect(signedIn, isNotNull);
        expect(signedIn!.jwt, isNotEmpty);

        await expectLater(
          db.confirmAuth(
            ConfirmResetPasswordAuthPayload(
              token: refusal.token,
              newPassword: 'third-password-roundtrip-3',
            ),
          ),
          throwsA(isA<InvalidOrExpiredResetPasswordLinkException>()),
          reason:
              'a one-time ticket that survives its use is a standing '
              'credential -- and this one travelled in a response body',
        );

        expect(
          await db
              .authenticate(
                'admins',
                const SignInPasswordAuthPayload(
                  email: email,
                  password: 'third-password-roundtrip-3',
                ),
              )
              .then((_) => 'signed in')
              .onError<AuthException>((_, _) => 'refused'),
          'refused',
          reason: 'the replayed ticket must not have changed the password',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('submitting the current password is refused and does NOT burn the '
        'ticket', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        const email = 'reuse@example.com';
        const password = 'old-password-reuse-1';
        const newPassword = 'new-password-reuse-2';

        await db.authenticate(
          'admins',
          const PasswordAuthPayload(email: email, password: password),
        );
        await db.requirePasswordReset(
          table: 'admins',
          email: email,
          reason: PasswordResetReason.temporaryPassword,
          byUserId: 'cli',
        );

        final refusal = await _captureRefusal(
          () => db.authenticate(
            'admins',
            const SignInPasswordAuthPayload(email: email, password: password),
          ),
        );

        await expectLater(
          db.confirmAuth(
            ConfirmResetPasswordAuthPayload(
              token: refusal.token,
              newPassword: password,
            ),
          ),
          throwsA(isA<PasswordReuseException>()),
        );

        // The ordering `reset_password.dart` is explicit about: the challenge
        // is consumed AFTER every check that can still reject the submission.
        // Spending it first would mean someone typing the password they
        // already have is told to request a whole new email -- and on the
        // forced path there is no email to request.
        await db.confirmAuth(
          ConfirmResetPasswordAuthPayload(
            token: refusal.token,
            newPassword: newPassword,
          ),
        );

        expect(
          await db.authenticate(
            'admins',
            const SignInPasswordAuthPayload(
              email: email,
              password: newPassword,
            ),
          ),
          isNotNull,
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'an emailed reset clears a forced requirement too',
      () async {
        if (!_runningOnDartVm) return;

        // The cross-door case. The requirement says "choose a new password",
        // not "choose it through the door we shut you out of", so the ordinary
        // forgot-my-password flow has to satisfy it. If it did not, an account
        // that reset by email would still be gated with no ticket in hand.
        debugInsecureTestMode = true;

        await withDb((db) async {
          const email = 'crossdoor@example.com';
          const password = 'old-password-crossdoor-1';
          const newPassword = 'new-password-crossdoor-2';

          final signUp = await db.authenticate(
            'users',
            const PasswordAuthPayload(email: email, password: password),
          );
          final userId = signUp!.user['id']! as String;

          await db.requirePasswordReset(
            table: 'users',
            email: email,
            reason: PasswordResetReason.compromised,
            byUserId: 'cli',
          );

          await db.sendResetPassword(
            'users',
            const ResetPasswordAuthPayload(email: email),
          );

          // Under insecure test mode the emailed secret is a known constant, so
          // the token can be rebuilt here exactly as the email would carry it.
          // The alternative is an SMTP capture server, which buys nothing this
          // assertion needs.
          final emailedToken = base64Encode(
            '$kInsecureTestResetPasswordSecret:$email'.codeUnits,
          );

          await db.confirmAuth(
            ConfirmResetPasswordAuthPayload(
              token: emailedToken,
              newPassword: newPassword,
            ),
          );

          expect(
            await db.passwordResetRequirement(table: 'users', userId: userId),
            isNull,
          );
          expect(
            await db.authenticate(
              'users',
              const SignInPasswordAuthPayload(
                email: email,
                password: newPassword,
              ),
            ),
            isNotNull,
            reason: 'and the account is no longer gated',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'OTP still signs in, and the requirement survives it',
      () async {
        if (!_runningOnDartVm) return;

        // The requirement is a statement about the PASSWORD credential.
        // Someone who proved possession of their mailbox has not used the
        // password, so they are not asked to change it -- and it stays unusable
        // until they do. Gating OTP as well would lock an account out of the
        // one door that could still let it in.
        debugInsecureTestMode = true;

        await withDb((db) async {
          const email = 'passwordless@example.com';
          const password = 'old-password-passwordless-1';

          final signUp = await db.authenticate(
            'users',
            const PasswordAuthPayload(email: email, password: password),
          );
          final userId = signUp!.user['id']! as String;

          await db.requirePasswordReset(
            table: 'users',
            email: email,
            reason: PasswordResetReason.passwordPolicy,
            byUserId: 'cli',
          );

          await db.sendOtp('users', const SendOtpAuthPayload(email: email));
          final otpSignIn = await db.confirmAuth(
            const VerifyOtpAuthPayload(email: email, code: kInsecureTestOtp),
          );

          expect(otpSignIn, isNotNull, reason: 'the OTP door stays open');
          expect(otpSignIn!.jwt, isNotEmpty);

          expect(
            await db.passwordResetRequirement(table: 'users', userId: userId),
            isNotNull,
            reason:
                'an OTP sign-in is not a new password, so it must not satisfy '
                'the requirement -- otherwise the control is lifted by the one '
                'door it deliberately left open',
          );

          await expectLater(
            db.authenticate(
              'users',
              const SignInPasswordAuthPayload(email: email, password: password),
            ),
            throwsA(isA<PasswordResetRequiredException>()),
            reason: 'and the password door is still shut',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'an OAuth-only collection refuses a requirement',
      () async {
        if (!_runningOnDartVm) return;

        await withDb((db) async {
          const email = 'partner@example.com';

          // Created through the OTP door, because there is no other.
          // `db.create` refuses an auth table outright ("Cannot create auth
          // records, use the auth API instead") and the OAuth door needs a
          // real provider round trip. What matters is only that the row
          // exists with no password: `_requirePasswordReset` looks the account
          // up FIRST, so without one it would throw "No account with email"
          // and prove nothing about the branch this test is named for.
          debugInsecureTestMode = true;
          await db.sendOtp('partners', const SendOtpAuthPayload(email: email));
          final created = await db.confirmAuth(
            const VerifyOtpAuthPayload(email: email, code: kInsecureTestOtp),
          );
          expect(created, isNotNull);
          debugInsecureTestMode = null;

          await expectLater(
            db.requirePasswordReset(
              table: 'partners',
              email: email,
              reason: PasswordResetReason.adminForced,
              byUserId: 'cli',
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('no password column'),
              ),
            ),
            reason:
                'writing a row here would be unenforceable by construction, and '
                'an operator who got a success would believe the account was '
                'constrained',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'clearing reports whether there was anything to clear',
      () async {
        if (!_runningOnDartVm) return;

        await withDb((db) async {
          const email = 'clearable@example.com';
          const password = 'old-password-clearable-1';

          await db.authenticate(
            'admins',
            const PasswordAuthPayload(email: email, password: password),
          );

          expect(
            await db.clearPasswordResetRequirement(
              table: 'admins',
              email: email,
            ),
            isFalse,
            reason:
                'nothing set -- and it must ANSWER that rather than throw, or a '
                'CLI clearing an already-satisfied requirement reports failure',
          );

          await db.requirePasswordReset(
            table: 'admins',
            email: email,
            reason: PasswordResetReason.adminForced,
            byUserId: 'cli',
          );

          expect(
            await db.clearPasswordResetRequirement(
              table: 'admins',
              email: email,
            ),
            isTrue,
          );

          expect(
            await db.authenticate(
              'admins',
              const SignInPasswordAuthPayload(email: email, password: password),
            ),
            isNotNull,
            reason: 'the escape hatch really lifts the gate',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

/// Runs [action] and returns the refusal it must raise.
///
/// `expectLater(..., throwsA(...))` proves the type but hands back nothing,
/// and every assertion here is about what the exception CARRIES -- the
/// ticket, the reason, the lifetime.
Future<PasswordResetRequiredException> _captureRefusal(
  Future<Object?> Function() action,
) async {
  try {
    final result = await action();
    fail('expected a PasswordResetRequiredException, got $result');
  } on PasswordResetRequiredException catch (e) {
    return e;
  }
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
    // The reset-email and OTP paths both reach for `courier` -- unlike the
    // password paths, which is why the other e2e files here get away without
    // it. `appConfig.email` is null, so `Courier` warns and returns rather
    // than opening an SMTP connection: nothing in this file needs an email
    // to actually arrive, only the challenge row it is built from.
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

/// The fixture only depends on `zonai_schema`, not on `zonai`, so it cannot
/// JIT-link a project-linked entry. Forcing Mailman/IPC workers skips that
/// re-exec and drives the migrate commands through the compiled worker
/// executables instead.
const _forceWorkersEnv = {'ZONAI_FORCE_WORKERS': '1'};

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: zonai_forced_password_reset
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
