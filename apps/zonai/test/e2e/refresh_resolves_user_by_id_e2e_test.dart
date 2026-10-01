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
import '../support/zonai_cli.dart';

/// Refresh must re-issue a session for the user the token belongs to.
///
/// It used to read the email out of the old token's `user` snapshot and sign
/// in whichever row holds that address *now*. An email is not an identity: an
/// admin can correct it (or an app can let users edit their own), and the old
/// address can then be registered by someone else -- at which point the first
/// user's live token refreshed into the second user's account. A row without
/// an email could not refresh at all.
///
/// The token carries the user's id, and the id is what a session belongs to.
void main() {
  group('refresh resolves the user by id (e2e)', () {
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

      projectRoot = createCanonicalTempSync('zonai_refresh_by_id_e2e_');
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
        appName: 'Refresh By Id E2E',
        passwordSecret: _passwordSecret,
        jwtSecret: _jwtSecret,
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

    tearDownAll(() {
      if (!_runningOnDartVm) return;
      deleteTempDirectory(projectRoot);
    });

    test('refresh re-issues a session for the same user', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final session = await db.authenticate(
          'users',
          const PasswordAuthPayload(
            email: 'same-user@example.com',
            password: 'same-user-password-1',
          ),
        );

        final refreshed = await db.refreshToken(session!.jwt);

        expect(refreshed, isNotNull);
        expect(refreshed!.user['id'], session.user['id']);
        expect(refreshed.jwt, isNot(session.jwt));
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('after an address moves to another account, a live token still '
        'refreshes into its own account', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        const original = 'moved-address@example.com';
        const replacement = 'moved-address-new@example.com';

        final admin = await db.authenticate(
          'admins',
          const PasswordAuthPayload(
            email: 'moved-address-admin@example.com',
            password: 'moved-address-admin-password-1',
          ),
        );
        final first = await db.authenticate(
          'users',
          const PasswordAuthPayload(
            email: original,
            password: 'first-user-password-1',
          ),
        );
        final firstId = first!.user['id']!;

        // An admin corrects the first user's address. The first user keeps
        // the token issued before the edit, and nothing about the edit
        // revokes it.
        await db.update(
          'users',
          UpdatePayload(
            where: Eq('id', firstId),
            updates: [
              Update.object({'email': replacement}),
            ],
            jwt: admin!.jwt,
          ),
        );

        // Someone else now registers the address the old token names.
        final second = await db.authenticate(
          'users',
          const PasswordAuthPayload(
            email: original,
            password: 'second-user-password-1',
          ),
        );
        final secondId = second!.user['id']!;
        expect(secondId, isNot(firstId));

        final refreshed = await db.refreshToken(first.jwt);

        expect(
          refreshed!.user['id'],
          firstId,
          reason:
              'the token belongs to the first user; refreshing it must not '
              'produce a session for whoever holds its old address now',
        );
        expect(refreshed.user['email'], replacement);
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a user whose row is gone cannot refresh', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final admin = await db.authenticate(
          'admins',
          const PasswordAuthPayload(
            email: 'refresh-admin@example.com',
            password: 'refresh-admin-password-1',
          ),
        );
        final user = await db.authenticate(
          'users',
          const PasswordAuthPayload(
            email: 'deleted-user@example.com',
            password: 'deleted-user-password-1',
          ),
        );

        final deleted = await db.delete(
          'users',
          DeletePayload(where: Eq('id', user!.user['id']!), jwt: admin!.jwt),
        );
        expect(deleted, 1);

        await expectLater(
          db.refreshToken(user.jwt),
          throwsA(isA<UserNotFoundAuthException>()),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

const _jwtSecret = 'refresh-by-id-e2e-Qm4Tz8VbNc2XkLp7RdHw5JsYf9Ga';
const _passwordSecret = 'refresh-by-id-e2e-pw-Lw6Hn3KcVx8PqZt2MdRy5BsJ4';

Future<void> _withDb(
  Settings settings,
  AppConfig appConfig,
  Future<void> Function(ZonaiDb db) body,
) async {
  late ZonaiDb db;
  await runMergedScopedFuture(
    () async {
      // The fixed resolver is honoured (`_run` prefers it over the config
      // worker), so every token here is signed with this file's secret.
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
name: zonai_admin_password_update_repro
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
