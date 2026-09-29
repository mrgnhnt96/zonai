import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
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

/// Anonymous accounts, end to end through a compiled fixture: a `users` table
/// that mixes in `AnonymousAuth` beside OTP and password sign-in, and a
/// `notes` table its rows own.
///
/// What is asserted is behaviour through the public `ZonaiDb` API -- an
/// account created with no address, kept reachable by its device credential,
/// and upgraded in place so that what it owned while anonymous is still its
/// own -- plus the refusals that make it safe: identity columns the sign-up
/// body and the owner cannot write, an anonymity claim a forged token cannot
/// shed, a code that only works for the session that asked for it, and an
/// address that cannot be taken twice.
void main() {
  group('anonymous auth (e2e)', () {
    late Directory projectRoot;
    late Settings settings;
    late AppConfig appConfig;

    setUpAll(() async {
      if (!_runningOnDartVm) return;

      var fixtureRoot = Directory(
        p.normalize(
          p.join(Directory.current.path, '..', '..', 'e2e', 'anonymous_auth'),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/anonymous_auth'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_anonymous_auth_e2e_');
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
        appName: 'Anonymous Auth E2E',
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

    setUp(() => debugInsecureTestMode = true);
    tearDown(() => debugInsecureTestMode = null);

    test('creates an address-less, unverified account and an anonymous '
        'session', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final created = await db.signInAnonymously(
          'users',
          object: {'display_name': 'guest'},
        );

        expect(created.user['email'], isNull);
        expect(created.user['is_verified'], _falsy);
        expect(created.user['display_name'], 'guest');
        expect(created.credential, startsWith('zonai_anon_'));

        final jwt = await db.parseJwt(created.jwt);
        expect(jwt!.isAnonymous, isTrue);
        expect(jwt.userId.value, created.user['id']);
      });
    }, timeout: _timeout);

    test(
      'the sign-up body cannot set the address or the verification flag',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          final created = await db.signInAnonymously(
            'users',
            object: {'email': 'smuggled@example.com', 'is_verified': true},
          );

          expect(created.user['email'], isNull);
          expect(created.user['is_verified'], _falsy);
        });
      },
      timeout: _timeout,
    );

    test('an anonymous owner cannot write their own address', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final created = await db.signInAnonymously('users');

        // Positive control: the table rules DO let an owner update their row,
        // so the refusal below is the identity guard, not a closed table.
        await db.update(
          'users',
          UpdatePayload(
            where: Eq('id', created.user['id']!),
            updates: [
              Update.object({'display_name': 'renamed'}),
            ],
            jwt: created.jwt,
          ),
        );

        await expectLater(
          db.update(
            'users',
            UpdatePayload(
              where: Eq('id', created.user['id']!),
              updates: [
                Update.object({'email': 'self-written@example.com'}),
              ],
              jwt: created.jwt,
            ),
          ),
          throwsA(anything),
        );
      });
    }, timeout: _timeout);

    test(
      'a re-signed token claiming not to be anonymous is not believed',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          final created = await db.signInAnonymously('users');
          final forged = _resign(
            created.jwt,
            (payload) => payload..remove('anonymous'),
          );

          // The forgery verifies -- it is signed with the server's own key --
          // so what is asserted is that the claim is ignored, not rejected.
          final parsed = await db.parseJwt(forged);
          expect(parsed, isNotNull);
          expect(parsed!.isAnonymous, isTrue);
        });
      },
      timeout: _timeout,
    );

    test('the device credential resumes the same account, and nothing else '
        'does', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final created = await db.signInAnonymously('users');

        final resumed = await db.resumeAnonymous(created.credential);
        expect(resumed.user['id'], created.user['id']);
        expect((await db.parseJwt(resumed.jwt))!.isAnonymous, isTrue);

        await expectLater(
          db.resumeAnonymous('zonai_anon_${'0' * 64}'),
          throwsA(isA<InvalidJwtException>()),
        );
        await expectLater(
          db.resumeAnonymous(created.jwt),
          throwsA(isA<InvalidJwtException>()),
        );
      });
    }, timeout: _timeout);

    test('upgrading keeps the id and everything the account owned, and '
        'retires every anonymous credential', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final created = await db.signInAnonymously('users');
        final userId = created.user['id']! as String;

        await db.create(
          'notes',
          CreatePayload(
            object: {'owner_id': userId, 'body': 'written while anonymous'},
            jwt: created.jwt,
          ),
        );

        await db.requestUpgrade(jwt: created.jwt, email: 'Ada@Example.com');
        final upgraded = await db.confirmUpgrade(
          jwt: created.jwt,
          email: 'ada@example.com',
          code: kInsecureTestOtp,
          password: 'ada-chose-this-password-1',
        );

        expect(upgraded.user['id'], userId);
        expect(upgraded.user['email'], 'ada@example.com');
        expect(upgraded.user['is_verified'], _truthy);

        final session = await db.parseJwt(upgraded.jwt);
        expect(session!.isAnonymous, isFalse);

        // Everything that proved "anonymous" is gone.
        await expectLater(
          db.parseJwt(created.jwt),
          throwsA(isA<JwtRecordNotFoundException>()),
        );
        await expectLater(
          db.resumeAnonymous(created.credential),
          throwsA(isA<InvalidJwtException>()),
        );

        // The note written while anonymous is still this account's.
        final note = await db.read(
          'notes',
          ViewPayload(where: Eq('owner_id', userId), jwt: upgraded.jwt),
        );
        expect(note['body'], 'written while anonymous');

        // And the account now signs in like any other.
        final signedIn = await db.authenticate(
          'users',
          const SignInPasswordAuthPayload(
            email: 'ada@example.com',
            password: 'ada-chose-this-password-1',
          ),
        );
        expect(signedIn!.user['id'], userId);
      });
    }, timeout: _timeout);

    test('a code only works for the session that asked for it', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final asker = await db.signInAnonymously('users');
        final other = await db.signInAnonymously('users');

        await db.requestUpgrade(jwt: asker.jwt, email: 'bound@example.com');

        await expectLater(
          db.confirmUpgrade(
            jwt: other.jwt,
            email: 'bound@example.com',
            code: kInsecureTestOtp,
          ),
          throwsA(isA<InvalidOrExpiredCodeException>()),
        );
      });
    }, timeout: _timeout);

    test('an address another account holds is refused after proof, and the '
        'anonymous account is left as it was', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        await db.authenticate(
          'users',
          const SignUpPasswordAuthPayload(
            email: 'taken@example.com',
            password: 'the-first-owner-password-1',
          ),
        );
        final anonymous = await db.signInAnonymously('users');

        // Same answer as for a free address: nothing learned before proof.
        await db.requestUpgrade(jwt: anonymous.jwt, email: 'TAKEN@example.com');

        await expectLater(
          db.confirmUpgrade(
            jwt: anonymous.jwt,
            email: 'TAKEN@example.com',
            code: kInsecureTestOtp,
          ),
          throwsA(isA<EmailInUseException>()),
        );

        final resumed = await db.resumeAnonymous(anonymous.credential);
        expect(resumed.user['email'], isNull);
      });
    }, timeout: _timeout);

    test('only an anonymous session can upgrade', () async {
      if (!_runningOnDartVm) return;

      await _withDb(settings, appConfig, (db) async {
        final verified = await db.authenticate(
          'users',
          const SignUpPasswordAuthPayload(
            email: 'already-has-one@example.com',
            password: 'already-has-one-password-1',
          ),
        );

        await expectLater(
          db.requestUpgrade(jwt: verified!.jwt, email: 'second@example.com'),
          throwsA(isA<NotAnonymousSessionException>()),
        );
      });
    }, timeout: _timeout);
  });
}

const _timeout = Timeout(Duration(minutes: 3));

// A row read back through the mutator carries SQLite's integers for a bool.
final _truthy = anyOf(isTrue, equals(1));
final _falsy = anyOf(isFalse, equals(0));

/// Generated per run, so no signing secret is committed. Long and varied
/// enough for AppConfig's checks.
final _jwtSecret = _randomSecret();
final _passwordSecret = _randomSecret();

String _randomSecret() => base64Url.encode(
  List<int>.generate(32, (_) => Random.secure().nextInt(256)),
);

/// Rewrites a real token's payload and signs the result with [_jwtSecret].
///
/// Mirrors [JwtGenerator]'s segment encoding exactly (unpadded base64url,
/// HS256 over `header.payload`), so what comes out is indistinguishable from a
/// token the server itself issued — apart from the claim.
String _resign(
  String token,
  Map<String, Object?> Function(Map<String, Object?> payload) edit,
) {
  final [header, payload, _] = token.split('.');
  final decoded =
      jsonDecode(utf8.decode(base64Url.decode(_pad(payload))))
          as Map<String, dynamic>;

  final tampered = edit(Map<String, Object?>.from(decoded));
  final segment = base64Url
      .encode(utf8.encode(jsonEncode(tampered)))
      .replaceAll('=', '');
  final signingInput = '$header.$segment';
  final signature = Hmac(
    sha256,
    utf8.encode(_jwtSecret),
  ).convert(utf8.encode(signingInput)).bytes;

  return '$signingInput.${base64Url.encode(signature).replaceAll('=', '')}';
}

String _pad(String segment) {
  final remainder = segment.length % 4;
  return remainder == 0
      ? segment
      : segment.padRight(segment.length + (4 - remainder), '=');
}

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
    // No email config in the fixture, so sending is a no-op; the upgrade code
    // is the fixed insecure-test-mode one.
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
name: zonai_anonymous_auth_fixture
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
