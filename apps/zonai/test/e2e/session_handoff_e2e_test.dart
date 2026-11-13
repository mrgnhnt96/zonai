import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

/// A signed-in session hands a command line a one-time code, and the command
/// line trades it for a session of its own: a separate session row, so
/// signing out of either leaves the other, and signing out everywhere ends
/// both.
void main() {
  group('session handoff (e2e)', () {
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

      projectRoot = createCanonicalTempSync('zonai_session_handoff_e2e_');
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
        appName: 'Session Handoff E2E',
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

    Future<_AuthResult> signIn(ZonaiDb db, String email) async {
      final session = await db.authenticate(
        'users',
        PasswordAuthPayload(email: email, password: 'handoff-password-1'),
      );
      return (jwt: session!.jwt, userId: session.user['id']);
    }

    Future<String> handOff(ZonaiDb db, String approving) async {
      final handoff = await db.createSessionHandoff(
        jwt: approving,
        codeChallenge: _codeChallenge,
        codeChallengeMethod: 'S256',
      );
      return handoff.code;
    }

    Matcher refused() => throwsA(isA<JwtRecordNotFoundException>());

    test(
      'z1: the code buys a new session and leaves the approving one alone',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          final browser = await signIn(db, 'handoff-new@example.com');
          final handoff = await db.createSessionHandoff(
            jwt: browser.jwt,
            codeChallenge: _codeChallenge,
            codeChallengeMethod: 'S256',
          );
          expect(
            handoff.expiresAt.difference(clock.now()).inMinutes,
            inInclusiveRange(4, 5),
          );

          final cli = await db.exchangeSessionHandoff(
            code: handoff.code,
            codeVerifier: _codeVerifier,
          );

          expect(cli.user['id'], browser.userId);
          expect(cli.jwt, isNot(browser.jwt));

          final cliClaims = await db.parseJwt(cli.jwt);
          final browserClaims = await db.parseJwt(browser.jwt);
          expect(cliClaims, isNotNull);
          expect(
            browserClaims,
            isNotNull,
            reason: 'the approving session must be untouched',
          );
          expect(cliClaims!.jwtId, isNot(browserClaims!.jwtId));
          expect(cliClaims.table, 'users');
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('z3: a code already traded is refused', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final browser = await signIn(db, 'handoff-reused@example.com');
        final code = await handOff(db, browser.jwt);

        await db.exchangeSessionHandoff(
          code: code,
          codeVerifier: _codeVerifier,
        );

        await expectLater(
          db.exchangeSessionHandoff(code: code, codeVerifier: _codeVerifier),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('z3: a code past its five minutes is refused', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final browser = await signIn(db, 'handoff-expired@example.com');
        final code = await handOff(db, browser.jwt);
        final later = clock.now().add(const Duration(minutes: 6));

        await withClock(
          Clock.fixed(later),
          () => expectLater(
            db.exchangeSessionHandoff(code: code, codeVerifier: _codeVerifier),
            throwsA(isA<CodeExpiredException>()),
          ),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('z3: a code that was never issued is refused', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        await expectLater(
          db.exchangeSessionHandoff(
            code: 'never-issued',
            codeVerifier: _codeVerifier,
          ),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('z6: signing out of the browser leaves the CLI signed in', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final browser = await signIn(db, 'handoff-browser-out@example.com');
        final cli = await db.exchangeSessionHandoff(
          code: await handOff(db, browser.jwt),
          codeVerifier: _codeVerifier,
        );

        await db.logout(browser.jwt);

        await expectLater(db.parseJwt(browser.jwt), refused());
        expect(await db.parseJwt(cli.jwt), isNotNull);
        expect(await db.refreshToken(cli.jwt), isNotNull);
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('z7: signing out everywhere ends the CLI session too', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final browser = await signIn(db, 'handoff-everywhere@example.com');
        final cli = await db.exchangeSessionHandoff(
          code: await handOff(db, browser.jwt),
          codeVerifier: _codeVerifier,
        );

        await db.logoutAll(browser.jwt);

        await expectLater(db.parseJwt(browser.jwt), refused());
        await expectLater(db.parseJwt(cli.jwt), refused());
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

/// RFC 7636 appendix B's pair. The exchange does not check it yet; the
/// test passes a matching pair so it keeps passing once it does.
const _codeVerifier = 'dBjftJeZ4CVP-mJM6CpwYkxOgVNLZYDmfnQi6KJOcPrhPlMnBR8F';
const _codeChallenge = 'E9cbbwIYb6fRSMcQxNjL4LzvDZ1kXTkZkZXSmrWiT9I';

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
