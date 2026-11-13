import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
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
        table: 'users',
        codeChallenge: _codeChallenge,
        codeChallengeMethod: 'S256',
      );
      return handoff.code;
    }

    Matcher refused() => throwsA(isA<JwtRecordNotFoundException>());

    Matcher notAllowed() => throwsA(isA<SessionHandoffNotAllowedException>());

    test(
      'z1: the code buys a new session and leaves the approving one alone',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          final browser = await signIn(db, 'handoff-new@example.com');
          final handoff = await db.createSessionHandoff(
            jwt: browser.jwt,
            table: 'users',
            codeChallenge: _codeChallenge,
            codeChallengeMethod: 'S256',
          );
          expect(
            handoff.expiresAt.difference(clock.now()).inMinutes,
            inInclusiveRange(4, 5),
          );

          final cli = await db.exchangeSessionHandoff(
            table: 'users',
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
          table: 'users',
          code: code,
          codeVerifier: _codeVerifier,
        );

        await expectLater(
          db.exchangeSessionHandoff(
            table: 'users',
            code: code,
            codeVerifier: _codeVerifier,
          ),
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
            db.exchangeSessionHandoff(
              table: 'users',
              code: code,
              codeVerifier: _codeVerifier,
            ),
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
            table: 'users',
            code: 'never-issued',
            codeVerifier: _codeVerifier,
          ),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'z2: a wrong verifier is refused, and the code is spent by it',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          final browser = await signIn(db, 'handoff-wrong-secret@example.com');
          final code = await handOff(db, browser.jwt);

          await expectLater(
            db.exchangeSessionHandoff(
              table: 'users',
              code: code,
              codeVerifier: '${_codeVerifier}x',
            ),
            throwsA(isA<InvalidOrExpiredCodeException>()),
          );

          await expectLater(
            db.exchangeSessionHandoff(
              table: 'users',
              code: code,
              codeVerifier: _codeVerifier,
            ),
            throwsA(isA<InvalidOrExpiredCodeException>()),
            reason: 'the wrong guess must have burned the code',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('z2: a code is not found under another table', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final browser = await signIn(db, 'handoff-other-table@example.com');
        final code = await handOff(db, browser.jwt);

        await expectLater(
          db.exchangeSessionHandoff(
            table: 'admins',
            code: code,
            codeVerifier: _codeVerifier,
          ),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('z4: a signed-out caller gets no code', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        await expectLater(
          db.createSessionHandoff(
            jwt: null,
            table: 'users',
            codeChallenge: _codeChallenge,
            codeChallengeMethod: 'S256',
          ),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('z4: an admin session gets no code', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final admin = await db.authenticate(
          'admins',
          const PasswordAuthPayload(
            email: 'handoff-admin@example.com',
            password: 'handoff-password-1',
          ),
        );

        await expectLater(
          db.createSessionHandoff(
            jwt: admin!.jwt,
            table: 'admins',
            codeChallenge: _codeChallenge,
            codeChallengeMethod: 'S256',
          ),
          notAllowed(),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('z4: an API token gets no code', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        await expectLater(
          db.createSessionHandoff(
            jwt: '${ApiTokenSecret.prefix}${'a' * 43}',
            table: 'users',
            codeChallenge: _codeChallenge,
            codeChallengeMethod: 'S256',
          ),
          throwsA(isA<ApiTokenNotAcceptedHereException>()),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'z4: a token from an outside identity provider gets no code',
      () async {
        if (!_runningOnDartVm) return;

        final trustingIdp = AppConfig(
          appName: appConfig.appName,
          passwordSecret: _passwordSecret,
          jwtSecret: _jwtSecret,
          baseUrl: appConfig.baseUrl,
          externalIdps: const [
            SharedSecretIdpConfig(
              issuer: _idpIssuer,
              audience: 'authenticated',
              authTable: 'users',
              secret: _idpSecret,
            ),
          ],
        );

        await _withDb(settings, trustingIdp, (db) async {
          final account = await signIn(db, 'handoff-outside@example.com');
          final outside = _outsideIdpJwt(sub: '${account.userId}');

          // The token is good for this account everywhere else.
          final claims = await db.parseJwt(outside);
          expect(claims?.userId.value, account.userId);

          await expectLater(
            db.createSessionHandoff(
              jwt: outside,
              table: 'users',
              codeChallenge: _codeChallenge,
              codeChallengeMethod: 'S256',
            ),
            throwsA(isA<InvalidJwtException>()),
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('z4: a session for another table gets no code', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final browser = await signIn(db, 'handoff-wrong-table@example.com');

        await expectLater(
          db.createSessionHandoff(
            jwt: browser.jwt,
            table: 'admins',
            codeChallenge: _codeChallenge,
            codeChallengeMethod: 'S256',
          ),
          notAllowed(),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('z4: a challenge made any way but S256 is refused', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final browser = await signIn(db, 'handoff-plain@example.com');

        await expectLater(
          db.createSessionHandoff(
            jwt: browser.jwt,
            table: 'users',
            codeChallenge: _codeVerifier,
            codeChallengeMethod: 'plain',
          ),
          throwsA(isA<InvalidBodyException>()),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('z6: signing out of the browser leaves the CLI signed in', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final browser = await signIn(db, 'handoff-browser-out@example.com');
        final cli = await db.exchangeSessionHandoff(
          table: 'users',
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
          table: 'users',
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

/// A PKCE pair: [_codeChallenge] is `base64url(sha256(_codeVerifier))`
/// without padding, worked out independently of the code under test.
const _codeVerifier = 'dBjftJeZ4CVP-mJM6CpwYkxOgVNLZYDmfnQi6KJOcPrhPlMnBR8F';
const _codeChallenge = 'hzKtMNh_70wNVHirYZvhJPn0J14a4m54zDIXmtfA-5s';

typedef _AuthResult = ({String jwt, Object? userId});

const _idpIssuer = 'https://abcdefgh.supabase.co/auth/v1';
const _idpSecret = 'e2e-outside-idp-jwt-secret';

/// A Supabase-shaped token for [sub], signed with the outside provider's
/// secret rather than zonai's.
String _outsideIdpJwt({required String sub}) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

  final signingInput =
      '${part(const {'alg': 'HS256', 'typ': 'JWT'})}.${part({'iss': _idpIssuer, 'aud': 'authenticated', 'sub': sub, 'role': 'authenticated', 'exp': clock.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}';
  final mac = Hmac(
    sha256,
    utf8.encode(_idpSecret),
  ).convert(utf8.encode(signingInput));
  return '$signingInput.${base64Url.encode(mac.bytes).replaceAll('=', '')}';
}

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
