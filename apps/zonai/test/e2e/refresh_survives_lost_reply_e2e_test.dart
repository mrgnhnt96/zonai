import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

import '../support/e2e_fixture.dart';
import '../support/temp_directory.dart';

/// A refresh must not sign the user out when its reply never arrives.
///
/// Refresh used to delete the old session as it issued the new one. When the
/// client never stored the reply -- iOS suspending the app mid-request, the
/// signal dropping -- it was left holding a token with no session behind it,
/// and its next refresh was a 401 the app read as a refused session.
///
/// The old session now lives until the new token is first used, so a client
/// that lost the reply can trade the old token again.
void main() {
  group('refresh survives a lost reply (e2e)', () {
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

      projectRoot = createCanonicalTempSync('zonai_refresh_lost_reply_e2e_');
      final repoRoot = fixtureRoot.parent.parent;
      copyFixtureTree(fixtureRoot, projectRoot);
      rewriteFixturePubspec(
        projectRoot: projectRoot,
        repoRoot: repoRoot,
        packageName: 'zonai_admin_password_update_repro',
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
        appName: 'Refresh Lost Reply E2E',
        passwordSecret: _passwordSecret,
        jwtSecret: _jwtSecret,
        baseUrl: 'http://localhost:8080',
      );

      await runMergedScopedFuture(() async {
        await runZonaiInFixture(projectRoot, const [
          'compile',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await runZonaiInFixture(projectRoot, const [
          'db',
          'migrate',
          'generate',
          '--name',
          'initialize',
          '--no-version-check',
          '--no-schema-version-check',
        ]);
        await runZonaiInFixture(projectRoot, const [
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

    Future<_AuthResult> signIn(ZonaiDb db, String email) async {
      final session = await db.authenticate(
        'users',
        PasswordAuthPayload(email: email, password: 'lost-reply-password-1'),
      );
      return (jwt: session!.jwt, userId: session.user['id']);
    }

    Matcher refused() => throwsA(isA<JwtRecordNotFoundException>());

    test(
      'the old token can be traded again while the new one is unused',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          final session = await signIn(db, 'lost-reply@example.com');

          // The reply carrying this token never reaches the client.
          final lost = await db.refreshToken(session.jwt);
          expect(lost, isNotNull);

          expect(
            await db.parseJwt(session.jwt),
            isNotNull,
            reason: 'the client still holds the old token and keeps using it',
          );

          final retried = await db.refreshToken(session.jwt);

          expect(retried!.user['id'], session.userId);
          expect(retried.jwt, isNot(lost!.jwt));
          expect(await db.parseJwt(retried.jwt), isNotNull);
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('once the new token is used, the old one is refused', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final session = await signIn(db, 'used-new-token@example.com');
        final refreshed = await db.refreshToken(session.jwt);

        expect(await db.parseJwt(refreshed!.jwt), isNotNull);

        await expectLater(db.parseJwt(session.jwt), refused());
        await expectLater(db.refreshToken(session.jwt), refused());
        expect(
          await db.parseJwt(refreshed.jwt),
          isNotNull,
          reason: 'retiring the old session must not touch the new one',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('refreshing with the new token counts as using it', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final session = await signIn(db, 'chained-refresh@example.com');
        final first = await db.refreshToken(session.jwt);
        final second = await db.refreshToken(first!.jwt);

        await expectLater(db.refreshToken(session.jwt), refused());
        expect(
          await db.parseJwt(first.jwt),
          isNotNull,
          reason: 'the token just traded is now the one in reserve',
        );
        expect(await db.parseJwt(second!.jwt), isNotNull);
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('logging out with the new token drops the old one too', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final session = await signIn(db, 'logout-new@example.com');
        final refreshed = await db.refreshToken(session.jwt);

        await db.logout(refreshed!.jwt);

        await expectLater(db.parseJwt(refreshed.jwt), refused());
        await expectLater(db.parseJwt(session.jwt), refused());
        await expectLater(db.refreshToken(session.jwt), refused());
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'logging out with the old token drops the unused new one too',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          final session = await signIn(db, 'logout-old@example.com');
          // Both replies lost: two unused sessions refreshed from this one.
          final lost = await db.refreshToken(session.jwt);
          final lostAgain = await db.refreshToken(session.jwt);

          await db.logout(session.jwt);

          await expectLater(db.parseJwt(session.jwt), refused());
          await expectLater(db.parseJwt(lost!.jwt), refused());
          await expectLater(db.parseJwt(lostAgain!.jwt), refused());
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

typedef _AuthResult = ({String jwt, Object? userId});

/// Generated per run, so no signing secret is committed. Long and varied
/// enough for AppConfig's checks.
final _jwtSecret = _randomSecret();
final _passwordSecret = _randomSecret();

String _randomSecret() => base64Url.encode(
  List<int>.generate(32, (_) => Random.secure().nextInt(256)),
);

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
