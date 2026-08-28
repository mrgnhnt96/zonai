import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/host_worker_registries.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/handlers/extensions/db_extensions.dart'
    show DbExtensions;
import 'package:zonai_schema/src/internal/tables/auth_challenge_table.dart'
    show AuthChallengeType, authChallenges;
import 'package:zonai_schema/src/internal/tables/jwt_table.dart' show jwts;
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
///   * `resetAdminPassword` revokes on its OWN, with no requirement in play.
///     The CLI's revocation today is a side effect of it ALSO calling
///     `requirePasswordReset` -- which `--no-force-reset` turns off, and which
///     no future caller of the method is obliged to call at all.
///   * the gate hands back a one-time ticket and mints NO session.
///   * a gated attempt does NOT fire `onSignIn`. The ordering is already
///     right; this pins it. The hook's default is not a no-op -- on a
///     HasEmail collection it sends a login notice -- so a regression moving
///     the gate below it would mail "you just signed in" to the owner of an
///     account whose sign-in was just refused.
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

    test('resetting an admin password revokes sessions on its OWN, with no '
        'requirement involved', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        const email = 'admin-reset@example.com';
        const oldPassword = 'old-password-admin-reset-1';
        const newPassword = 'new-password-admin-reset-1';

        final signUp = await db.authenticate(
          'admins',
          const PasswordAuthPayload(email: email, password: oldPassword),
        );
        expect(signUp, isNotNull);
        final userId = signUp!.user['id']! as String;
        final token = signUp.jwt;

        // The control: the session works right now, so its later failure is
        // caused by the reset rather than by never having been valid.
        expect(await db.parseJwt(token), isNotNull);

        // The METHOD, deliberately -- not `zonai db admin reset-password`.
        // The CLI happens to revoke today by ALSO calling
        // `requirePasswordReset`, which `--no-force-reset` turns off; driving
        // the CLI here would ride on that side effect and prove nothing about
        // the method every future caller will reach for.
        await db.resetAdminPassword(email: email, newPassword: newPassword);

        expect(
          await db.passwordResetRequirement(table: 'admins', userId: userId),
          isNull,
          reason:
              'THE control for this test. No requirement was set, so the '
              'revocation below can only have come from `resetAdminPassword` '
              'itself -- which is the point: the safety has to live in the '
              'method, or `--no-force-reset` and every future caller opt out '
              'of it without ever saying so',
        );

        expect(
          await _sessionCount(db, userId),
          0,
          reason:
              'counted, not inferred: a `_jwt` row surviving the reset is a '
              'session minted by the password that was just replaced, and it '
              'goes on working for the rest of jwtExpiresIn',
        );

        await expectLater(
          db.parseJwt(token),
          throwsA(isA<JwtRecordNotFoundException>()),
        );

        // And the reset itself still did its job -- a revocation that also
        // broke the password change would satisfy every assertion above.
        expect(
          await db.authenticate(
            'admins',
            const SignInPasswordAuthPayload(
              email: email,
              password: newPassword,
            ),
          ),
          isNotNull,
          reason: 'the new password signs in',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a gated sign-in mints no session and hands back a ticket', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        const email = 'gated@example.com';
        const password = 'old-password-gated-1';

        final signUp = await db.authenticate(
          'admins',
          const PasswordAuthPayload(email: email, password: password),
        );
        final userId = signUp!.user['id']! as String;
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

        // "Mints no session" asserted as a COUNT of `_jwt` rows, not as
        // "the call threw". The gate sits after the password verifies and
        // before anything mints, records or announces a session -- move it
        // one line later and this is the only assertion that notices, since
        // the caller sees an exception either way. Setting the requirement
        // revoked the sign-up's session, so the right number here is zero.
        expect(
          await _sessionCount(db, userId),
          0,
          reason:
              'a JWT recorded in `_jwt` has been handed to a caller who is '
              'under no obligation to discard it',
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
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a gated sign-in does not fire onSignIn', () async {
      if (!_runningOnDartVm) return;

      final recorder = _RecordingAdminsExtension();
      HostWorkerRegistries.extensions = DbExtensions(extensions: [recorder]);
      addTearDown(() => HostWorkerRegistries.extensions = null);

      await withDb((db) async {
        const email = 'hooked@example.com';
        const password = 'old-password-hooked-1';

        await db.authenticate(
          'admins',
          const PasswordAuthPayload(email: email, password: password),
        );

        // THE POSITIVE CONTROL, and it is not optional. "The hook did not
        // fire" is only evidence if this recorder fires at all, and with no
        // extension registered `_runExtension` returns early -- so `onSignIn`
        // could not fire whatever the gate did, and the assertion below would
        // pass while proving nothing. Not hypothetical: it is exactly what
        // this test did on the first run that registered no extension.
        expect(
          await db.authenticate(
            'admins',
            const SignInPasswordAuthPayload(email: email, password: password),
          ),
          isNotNull,
        );
        expect(
          recorder.signIns.where((e) => e == email).length,
          1,
          reason:
              'an ordinary sign-in fires onSignIn exactly once -- so a zero '
              'below is the gate, not a recorder that never worked',
        );

        await db.requirePasswordReset(
          table: 'admins',
          email: email,
          reason: PasswordResetReason.compromised,
          byUserId: 'cli',
        );

        await expectLater(
          db.authenticate(
            'admins',
            const SignInPasswordAuthPayload(email: email, password: password),
          ),
          throwsA(isA<PasswordResetRequiredException>()),
        );

        expect(
          recorder.signIns.where((e) => e == email).length,
          1,
          reason:
              'STILL one, counted rather than inferred: the gate throws at the '
              '`reset_required` step, two steps before `ext_hook`, and this '
              "pins it there. `onSignIn`'s default is not a no-op -- on any "
              'HasEmail collection it sends a login notice -- so a regression '
              "moving the gate below the hook would email the account's owner "
              '"you just signed in" at the moment their sign-in was refused, '
              'during a compromise response, which is when that mail is most '
              'likely to be believed and most wrong',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a WRONG password against a gated account is an ordinary 401 with '
        'no ticket', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        const email = 'oracle@example.com';
        const password = 'old-password-oracle-1';

        await db.authenticate(
          'admins',
          const PasswordAuthPayload(email: email, password: password),
        );
        await db.requirePasswordReset(
          table: 'admins',
          email: email,
          reason: PasswordResetReason.compromised,
          byUserId: 'cli',
        );

        // The gate runs AFTER the password verifies, and it has to stay
        // there. Raising the refusal on a wrong password would turn the
        // requirement into the enumeration oracle the whole "Failed sign-in"
        // contract exists to prevent -- an unauthenticated caller could tell a
        // gated account from any other by guessing one wrong password, and
        // would be handed a live reset ticket for the privilege.
        await expectLater(
          db.authenticate(
            'admins',
            const SignInPasswordAuthPayload(
              email: email,
              password: 'not-the-password',
            ),
          ),
          throwsA(isA<InvalidPasswordOrEmailException>()),
          reason: 'indistinguishable from any other wrong password',
        );

        expect(
          await _resetChallengeCount(db, email),
          0,
          reason:
              'and no ticket was minted -- a `passwordReset` challenge row '
              'written here is a credential handed to someone who failed to '
              'authenticate',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

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

    test('an emailed reset clears a forced requirement too', () async {
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
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('OTP still signs in, and the requirement survives it', () async {
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
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('an OAuth-only collection refuses a requirement', () async {
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
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('clearing reports whether there was anything to clear', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        const email = 'clearable@example.com';
        const password = 'old-password-clearable-1';

        await db.authenticate(
          'admins',
          const PasswordAuthPayload(email: email, password: password),
        );

        expect(
          await db.clearPasswordResetRequirement(table: 'admins', email: email),
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
          await db.clearPasswordResetRequirement(table: 'admins', email: email),
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
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

/// How many live `passwordReset` challenges exist for one address.
///
/// `canConsume` rather than "any row": a spent or expired ticket is not a
/// credential, and counting those would make this assertion fail for a reason
/// it is not about.
Future<int> _resetChallengeCount(ZonaiDb db, String email) async {
  final raw = await db.open();
  final rows = await raw
      .select()
      .from(authChallenges)
      .where(
        authChallenges.target.equals(email) &
            authChallenges.type.equals(AuthChallengeType.passwordReset) &
            authChallenges.canConsume.isTrue(),
      );
  return rows.length;
}

/// How many live `_jwt` rows one account holds.
///
/// Read straight off the internal table rather than inferred from whether some
/// token still parses: "no session was minted" is a statement about what was
/// WRITTEN, and a token nobody kept a reference to would let an
/// inference-based check pass over a row that is really there.
Future<int> _sessionCount(ZonaiDb db, String userId) async {
  final raw = await db.open();
  final rows = await raw
      .select()
      .from(jwts)
      .where(jwts.userId.equals(UnknownId(userId)));
  return rows.length;
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

/// A stand-in for the fixture's `admins` table.
///
/// Declared here because the recorder below has to exist in THIS process,
/// while the fixture package is only ever compiled into a temporary project
/// and never linked into the test. Two columns, not six: `safeCreate` walks
/// the table's own columns and `fromRow` reads only what is declared, so the
/// rest of the row is passed over. A rename of `id` or `email` in the fixture
/// makes this throw rather than quietly record nothing -- a loud failure,
/// which is the only thing that makes a second declaration of one table
/// tolerable.
final class _HookedAdminId implements Id {
  const _HookedAdminId(this.value);

  factory _HookedAdminId.generate() =>
      _HookedAdminId('${DateTime.now().microsecondsSinceEpoch}_hook');

  @override
  final String value;

  @override
  String toString() => value;
}

final class _HookedAdmin {
  _HookedAdmin({required this.id, required this.email});

  final _HookedAdminId id;
  final String email;
}

final class _HookedAdminTable extends AuthTable<_HookedAdmin> {
  _HookedAdminTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: _HookedAdminId.new,
        generate: _HookedAdminId.generate,
      ),
      email = $.email('email', (s) => s.email);

  @override
  _HookedAdmin fromRow(RowReader read) =>
      _HookedAdmin(id: read(id), email: read(email));

  final IdColumn<_HookedAdminId> id;
  final EmailColumn email;
}

final _hookedAdmins = authTable('admins', _HookedAdminTable.new);

/// Records every `onSignIn` FIRING, in memory.
///
/// In memory, and registered through [HostWorkerRegistries], for two reasons.
///
/// The first is that the assertion needs an extension to exist AT ALL: with
/// no project extension `_runExtension` returns early, so `onSignIn` cannot
/// fire whatever the gate does, and "no hook fired" would be vacuous. The
/// positive control in the test is what catches that.
///
/// The second is that the obvious alternative -- an extension in the fixture
/// -- is worse than it looks. It makes every auth event in every test spawn
/// the compiled extensions worker, and MEASURED on this suite that reds three
/// unrelated tests: a second DB connection turns `_revokeAllSessions` into
/// `SqliteException(5): database is locked`, and the worker's last stdout
/// chunk lands after teardown as `Bad state: Cannot add new events after
/// calling close`. Both are worth their own leaf; neither is this one.
///
/// It also records the hook BODY running, which is the thing being asserted.
/// A `mutate.create.one` would not: an extension's mutations are executed by
/// `_executeEffects()` at the `effects` step, one step AFTER `ext_hook`, so a
/// regression putting the gate between the two would fire the hook and still
/// write no row -- passing over exactly the regression this exists to catch.
final class _RecordingAdminsExtension extends Extension<_HookedAdmin>
    with AuthExtension<_HookedAdmin> {
  _RecordingAdminsExtension() : super(_hookedAdmins);

  final signIns = <String>[];

  @override
  Future<void> onSignIn(_HookedAdmin user, Jwt? jwt) async {
    // Deliberately not calling the default, which sends a login notice. What
    // is being asserted is whether this body ran.
    signIns.add(user.email);
  }
}
