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

import '../support/raindrop_package_roots.dart';

/// Reproduces admin-UI password bugs on generic row save:
///
/// 1. **Update** — the admin UI sends a single-row edit as one [ObjectUpdate]
///    containing all changed columns. `_hashPasswordUpdates`
///    (apps/zonai/lib/src/db_mutator/zonai_db/parts/update.dart) hashes the
///    new password in place on that map, but its `ObjectUpdate` branch used
///    to `continue` without ever adding the (now-correctly-hashed) update
///    back to the result list, so the whole update never reached SQL.
///
/// 2. **Create** — the admin UI creates a row via a plain object map that
///    includes the password column. `_create` / `_createMany` used to insert
///    that value without hashing, so sign-in failed (verify expects Argon2).
void main() {
  group('admin password mutation e2e', () {
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
            'admin_password_update_repro',
          ),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/admin_password_update_repro'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = Directory.systemTemp.createTempSync(
        'zonai_admin_password_update_e2e_',
      );
      final repoRoot = fixtureRoot.parent.parent;
      final raindropPackages = RaindropPackageRoots.fromPackageConfig();
      _copyTree(fixtureRoot, projectRoot);
      _rewritePubspecPaths(
        projectRoot: projectRoot,
        repoRoot: repoRoot,
        raindropPackages: raindropPackages,
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
        appName: 'Admin Password Update E2E',
        passwordSecret: 'e2e-password-pepper',
        jwtSecret: 'e2e-zonai-jwt-secret',
        baseUrl: 'http://localhost:8080',
      );

      await runMergedScopedFuture(() async {
        await _runZonai(projectRoot, ['compile', '--no-version-check']);
        await _runZonai(projectRoot, [
          'db',
          'migrate',
          'generate',
          '--name',
          'initialize',
          '--no-version-check',
        ]);
        await _runZonai(projectRoot, [
          'db',
          'migrate',
          'apply',
          '--no-version-check',
        ]);

        final extensionsExe = File(
          p.join(
            projectRoot.path,
            '.zonai',
            'executables',
            'db_extensions.exe',
          ),
        );
        expect(
          extensionsExe.existsSync(),
          isTrue,
          reason: 'compile must produce db_extensions.exe',
        );
      }, override: _e2eScopeOverrides(settings));
    });

    tearDownAll(() {
      projectRoot.deleteSync(recursive: true);
    });

    test('admin can sign in with a new password after editing their own row '
        "(admin's own account, edited via a generic ObjectUpdate like the "
        'admin UI sends)', () async {
      if (!_runningOnDartVm) {
        return;
      }

      late ZonaiDb db;
      await runMergedScopedFuture(
        () async {
          db = ZonaiDb();
          try {
            const email = 'admin@example.com';
            const oldPassword = 'old-admin-password-1';
            const newPassword = 'new-admin-password-2';

            final signUp = await db.authenticate(
              'admins',
              const PasswordAuthPayload(email: email, password: oldPassword),
            );
            expect(signUp, isNotNull);
            final adminId = signUp!.user['id'];
            final adminToken = signUp.jwt;
            expect(adminId, isNotNull);

            await db.update(
              'admins',
              UpdatePayload(
                where: Eq('id', adminId!),
                updates: [
                  Update.object({'password': newPassword}),
                ],
                jwt: adminToken,
              ),
            );

            await expectLater(
              db.authenticate(
                'admins',
                const PasswordAuthPayload(email: email, password: oldPassword),
              ),
              throwsA(isA<InvalidPasswordOrEmailException>()),
              reason:
                  'the old password must stop working once the admin '
                  'sets a new one',
            );

            final signInWithNewPassword = await db.authenticate(
              'admins',
              const PasswordAuthPayload(email: email, password: newPassword),
            );
            expect(
              signInWithNewPassword,
              isNotNull,
              reason:
                  'the new password must work immediately after the '
                  'admin edits their own password',
            );
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
    }, timeout: const Timeout(Duration(minutes: 2)));

    test("admin can sign in a regular user with the user's new password after "
        'the admin edits that user (a different, non-admin row, edited via a '
        'generic ObjectUpdate like the admin UI sends)', () async {
      if (!_runningOnDartVm) {
        return;
      }

      late ZonaiDb db;
      await runMergedScopedFuture(
        () async {
          db = ZonaiDb();
          try {
            const adminEmail = 'admin2@example.com';
            const adminPassword = 'admin-password-3';
            const userEmail = 'regular-user@example.com';
            const oldPassword = 'old-user-password-1';
            const newPassword = 'new-user-password-2';

            final adminSignUp = await db.authenticate(
              'admins',
              const PasswordAuthPayload(
                email: adminEmail,
                password: adminPassword,
              ),
            );
            expect(adminSignUp, isNotNull);
            final adminToken = adminSignUp!.jwt;

            final userSignUp = await db.authenticate(
              'users',
              const PasswordAuthPayload(
                email: userEmail,
                password: oldPassword,
              ),
            );
            expect(userSignUp, isNotNull);
            final userId = userSignUp!.user['id'];
            expect(userId, isNotNull);

            await db.update(
              'users',
              UpdatePayload(
                where: Eq('id', userId!),
                updates: [
                  Update.object({'password': newPassword}),
                ],
                jwt: adminToken,
              ),
            );

            await expectLater(
              db.authenticate(
                'users',
                const PasswordAuthPayload(
                  email: userEmail,
                  password: oldPassword,
                ),
              ),
              throwsA(isA<InvalidPasswordOrEmailException>()),
              reason:
                  "the user's old password must stop working once the "
                  'admin sets a new one for them',
            );

            final signInWithNewPassword = await db.authenticate(
              'users',
              const PasswordAuthPayload(
                email: userEmail,
                password: newPassword,
              ),
            );
            expect(
              signInWithNewPassword,
              isNotNull,
              reason:
                  "the user's new password must work immediately after "
                  'the admin edits it for them',
            );
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
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a non-password column sent in the same ObjectUpdate as the password '
        'is also persisted, not silently dropped along with it', () async {
      if (!_runningOnDartVm) {
        return;
      }

      late ZonaiDb db;
      await runMergedScopedFuture(
        () async {
          db = ZonaiDb();
          try {
            const email = 'admin3@example.com';
            const oldPassword = 'old-admin-password-4';
            const newPassword = 'new-admin-password-5';

            final signUp = await db.authenticate(
              'admins',
              const PasswordAuthPayload(email: email, password: oldPassword),
            );
            expect(signUp, isNotNull);
            expect(
              signUp!.user['is_verified'],
              isNot(_truthy),
              reason: 'sign-up must not verify the account by default',
            );
            final adminId = signUp.user['id'];
            final adminToken = signUp.jwt;
            expect(adminId, isNotNull);

            await db.update(
              'admins',
              UpdatePayload(
                where: Eq('id', adminId!),
                updates: [
                  Update.object({'password': newPassword, 'is_verified': true}),
                ],
                jwt: adminToken,
              ),
            );

            final rows = await db.list(
              'admins',
              ListPayload(where: Eq('id', adminId), jwt: adminToken),
            );
            expect(
              rows.items.single['is_verified'],
              _truthy,
              reason:
                  'a column updated alongside the password in the same '
                  'ObjectUpdate must not be dropped along with the fix '
                  'for the password field',
            );

            final signInWithNewPassword = await db.authenticate(
              'admins',
              const PasswordAuthPayload(email: email, password: newPassword),
            );
            expect(signInWithNewPassword, isNotNull);
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
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('admin can sign in a user created via a generic create (like the '
        'admin UI sends) with the password supplied at create time', () async {
      if (!_runningOnDartVm) {
        return;
      }

      late ZonaiDb db;
      await runMergedScopedFuture(
        () async {
          db = ZonaiDb();
          try {
            const adminEmail = 'admin-create@example.com';
            const adminPassword = 'admin-create-password-1';
            const userEmail = 'created-user@example.com';
            const userPassword = 'created-user-password-1';

            final adminSignUp = await db.authenticate(
              'admins',
              const PasswordAuthPayload(
                email: adminEmail,
                password: adminPassword,
              ),
            );
            expect(adminSignUp, isNotNull);
            final adminToken = adminSignUp!.jwt;

            await db.create(
              'users',
              CreatePayload(
                object: {
                  'email': userEmail,
                  'password': userPassword,
                  'is_verified': false,
                },
                jwt: adminToken,
              ),
            );

            await expectLater(
              db.authenticate(
                'users',
                const PasswordAuthPayload(
                  email: userEmail,
                  password: 'wrong-password',
                ),
              ),
              throwsA(isA<InvalidPasswordOrEmailException>()),
              reason:
                  'a wrong password must fail against a row created via '
                  'the generic create path',
            );

            final signIn = await db.authenticate(
              'users',
              const PasswordAuthPayload(
                email: userEmail,
                password: userPassword,
              ),
            );
            expect(
              signIn,
              isNotNull,
              reason:
                  'the password supplied at create time must work for '
                  'sign-in (it must be hashed before insert, not stored '
                  'as plain text)',
            );
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
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('admin can sign in an admin created via a generic create (like the '
        "admin UI's 'new row' form) with the password supplied at create "
        'time', () async {
      if (!_runningOnDartVm) {
        return;
      }

      late ZonaiDb db;
      await runMergedScopedFuture(
        () async {
          db = ZonaiDb();
          try {
            const bootstrapEmail = 'bootstrap-admin@example.com';
            const bootstrapPassword = 'bootstrap-admin-password-1';
            const createdEmail = 'created-admin@example.com';
            const createdPassword = 'created-admin-password-1';

            final bootstrap = await db.authenticate(
              'admins',
              const PasswordAuthPayload(
                email: bootstrapEmail,
                password: bootstrapPassword,
              ),
            );
            expect(bootstrap, isNotNull);
            final adminToken = bootstrap!.jwt;

            await db.create(
              'admins',
              CreatePayload(
                object: {
                  'email': createdEmail,
                  'password': createdPassword,
                  'is_verified': false,
                },
                jwt: adminToken,
              ),
            );

            final signIn = await db.authenticate(
              'admins',
              const PasswordAuthPayload(
                email: createdEmail,
                password: createdPassword,
              ),
            );
            expect(
              signIn,
              isNotNull,
              reason:
                  'an admin row created via the generic create path must '
                  'be sign-in-able with the password that was supplied',
            );
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
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

/// Matches a boolean column's wire value, whether the driver reports it as
/// `true`/`false` or `1`/`0`.
final Matcher _truthy = predicate<Object?>(
  (value) => value == true || value == 1,
  'truthy',
);

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
  final result = await Process.run(Platform.resolvedExecutable, [
    'run',
    zonaiEntry,
    ...args,
  ], workingDirectory: projectRoot.path);
  expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
}

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
  required RaindropPackageRoots raindropPackages,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: zonai_admin_password_update_repro
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaRoot)}
  raindrop:
    path: ${jsonEncode(raindropPackages.raindrop)}

dependency_overrides:
  raindrop:
    path: ${jsonEncode(raindropPackages.raindrop)}
  raindrop_sqlite:
    path: ${jsonEncode(raindropPackages.raindropSqlite)}
  resqlite:
    path: ${jsonEncode(raindropPackages.resqlite)}
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
