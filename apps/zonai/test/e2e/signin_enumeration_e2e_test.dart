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

/// Reproduces the "sign-in leaks whether an account exists" report.
///
/// `POST /auth/sign-in` builds a [SignInPasswordAuthPayload], but
/// `_authenticatePassword` only ever looked at the *base* type: when no auth
/// record matched the email it fell through to `_signUpWithPassword`,
/// regardless of which endpoint the caller used. So a sign-in for an unknown
/// address tried to **create** that account:
///
///  * on a table whose only columns are the auth ones, the account is created
///    and sign-in answers 200 with a session — unauthenticated provisioning
///    of an address the caller does not control, not merely a leak;
///  * on a table with a required column that only a sign-up body carries
///    (the reported schema had `name`), the insert casts null → HTTP 500,
///    while a wrong password on a *real* account answers 401. The status code
///    alone told the caller whether the address was registered.
///
/// Both branches are asserted below, on one fixture: `users` carries a
/// required `name`, so the 500 case is the direct repro, and the
/// no-account-created assertion covers the silent-signup case.
void main() {
  group('sign-in account enumeration e2e', () {
    late Directory projectRoot;
    late Directory fixtureRoot;
    late Settings settings;
    late AppConfig appConfig;

    const table = 'users';
    const realEmail = 'real.user@example.com';
    const realPassword = 'Test1234!';
    const unknownEmail = 'nobody.at.all@example.com';
    const wrongPassword = 'WrongPassword9!';

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
            'signin_enumeration_repro',
          ),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/signin_enumeration_repro'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_signin_enumeration_e2e_');
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
        appName: 'Sign-in Enumeration E2E',
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

    tearDownAll(() {
      if (!_runningOnDartVm) {
        return;
      }
      deleteTempDirectory(projectRoot);
    });

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

    test(
      'an unknown email is rejected exactly like a wrong password',
      () async {
        if (!_runningOnDartVm) {
          return;
        }

        await withDb((db) async {
          // 01 — create a real account through the sign-up path.
          final signUp = await db.authenticate(
            table,
            const SignUpPasswordAuthPayload(
              email: realEmail,
              password: realPassword,
              object: {'name': 'Real User'},
            ),
          );
          expect(signUp, isNotNull, reason: 'sign-up must create the account');

          // 02 — wrong password on an account that exists.
          Object? existingFailure;
          try {
            await db.authenticate(
              table,
              const SignInPasswordAuthPayload(
                email: realEmail,
                password: wrongPassword,
              ),
            );
            fail('a wrong password must not authenticate');
          } on Object catch (e) {
            existingFailure = e;
          }

          expect(
            existingFailure,
            isA<InvalidPasswordOrEmailException>(),
            reason: 'the wrong-password path is the intended 401',
          );

          // 03 — byte-identical but for the address: an email nobody owns.
          Object? unknownFailure;
          try {
            await db.authenticate(
              table,
              const SignInPasswordAuthPayload(
                email: unknownEmail,
                password: wrongPassword,
              ),
            );
            fail(
              'signing in with an unregistered email must not succeed — '
              'falling through to sign-up creates the account and hands '
              'back a session',
            );
          } on Object catch (e) {
            unknownFailure = e;
          }

          expect(
            unknownFailure,
            isA<InvalidPasswordOrEmailException>(),
            reason:
                'an unknown email must fail the same way a wrong password '
                'does; anything else (a 500 from the sign-up insert, or a '
                'distinct "user not found" message) answers "does this '
                'address have an account?" for an unauthenticated caller',
          );

          // The user-facing text is what the client actually compares, and
          // it is what Picto's own contract test asserts. Two exception
          // types that both map to 401 but render different bodies are
          // still an oracle.
          expect(
            '$unknownFailure',
            '$existingFailure',
            reason: 'both failures must render the same message',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a failed sign-in never creates the account it was given',
      () async {
        if (!_runningOnDartVm) {
          return;
        }

        await withDb((db) async {
          try {
            await db.authenticate(
              table,
              const SignInPasswordAuthPayload(
                email: unknownEmail,
                password: wrongPassword,
              ),
            );
          } on Object {
            // asserted by the test above; here we only care about the side
            // effect the attempt may have left behind.
          }

          final rows = await db.list(
            table,
            ListPayload(where: Eq('email', unknownEmail)),
          );

          expect(
            rows.items,
            isEmpty,
            reason: 'sign-in must never insert a row',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    // `users` carries a required `name`, so the sign-up insert this used to
    // fall through to had something to fail on and the caller saw a 500.
    // `bare_users` carries nothing beyond the auth columns, so there is
    // nothing to fail on: the insert succeeds. Before the fix this call
    // returned a valid session for an address nobody had registered, from
    // the endpoint that is supposed to only authenticate.
    test(
      'sign-in on a table with no required columns refuses to provision',
      () async {
        if (!_runningOnDartVm) {
          return;
        }

        await withDb((db) async {
          Object? failure;
          Object? result;
          try {
            result = await db.authenticate(
              'bare_users',
              const SignInPasswordAuthPayload(
                email: unknownEmail,
                password: wrongPassword,
              ),
            );
          } on Object catch (e) {
            failure = e;
          }

          expect(
            result,
            isNull,
            reason:
                'sign-in returned a session for an address nobody registered '
                '— the account was created on the spot',
          );
          expect(failure, isA<InvalidPasswordOrEmailException>());

          final rows = await db.list(
            'bare_users',
            ListPayload(where: Eq('email', unknownEmail)),
          );
          expect(rows.items, isEmpty, reason: 'no row may be created');
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
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
name: zonai_signin_enumeration_repro
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
