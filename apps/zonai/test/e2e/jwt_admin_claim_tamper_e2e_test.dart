import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/payloads/payloads.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/jwt_generator.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../support/temp_directory.dart';

/// Privilege escalation via the `admin` claim, verified live before the fix:
///
/// > "a token whose `admin.isAdmin` is flipped and re-signed is honored
/// > (flip→false made the same session lose access → the flag is read from
/// > the token, not the DB)".
///
/// `_validateJwt` looked the token's `jwtId` up in `_jwt` and returned the
/// caller's `Jwt` unchanged, so a *fully forged* token was rejected but a
/// *tampered real* one was not. Anyone who could sign — which, with a
/// guessable HS256 key, meant anyone — could hand themselves admin.
///
/// The fix re-derives `admin` from the registered schema on every validation.
/// These tests run against a real compiled project so the derivation goes
/// through the actual operations worker, not a stub, and every token here is
/// cryptographically valid: each tamper is asserted to *verify* before it is
/// asserted not to be *honoured*, so a passing test can never be a passing
/// signature check in disguise.
void main() {
  group('JWT admin claim tampering (e2e)', () {
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

      projectRoot = createCanonicalTempSync('zonai_jwt_admin_tamper_e2e_');
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
        appName: 'JWT Admin Tamper E2E',
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

    test(
      'a re-signed token that flips a user to admin is not honoured',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          final session = await db.authenticate(
            'users',
            const PasswordAuthPayload(
              email: 'tamper-user@example.com',
              password: 'tamper-user-password-1',
            ),
          );
          expect(session, isNotNull);

          final honest = await db.parseJwt(session!.jwt);
          expect(
            honest!.admin.isAdmin,
            isFalse,
            reason:
                '`users` is a plain auth table, so its tokens are not admin',
          );

          final forged = _resign(
            session.jwt,
            (payload) => payload
              ..['admin'] = <String, Object?>{'isAdmin': true, 'canEdit': true},
          );

          // The control that makes the assertion below mean something: the
          // forgery is a valid HS256 token carrying the escalated claim. If it
          // is refused, it is refused on the claim, not on the signature.
          final verified = await JwtGenerator(
            jwtSecret: _jwtSecret,
          ).verify(forged);
          expect(
            verified,
            isNotNull,
            reason: 'the tampered token must still verify against the key',
          );
          expect(
            (verified!['admin'] as Map)['isAdmin'],
            isTrue,
            reason: 'the escalated claim must actually be in the token',
          );
          expect(
            Jwt.fromJson(Map<String, dynamic>.from(verified)).admin.isAdmin,
            isTrue,
            reason:
                'and `Jwt.fromJson` must still read it off the wire — that is '
                'precisely what must no longer be trusted',
          );

          final parsed = await db.parseJwt(forged);
          expect(parsed, isNotNull);
          expect(
            parsed!.admin.isAdmin,
            isFalse,
            reason: 'the tampered admin claim must be discarded, not honoured',
          );
          expect(parsed.admin.canEdit, isNot(isTrue));
          expect(
            parsed.userId.value,
            honest.userId.value,
            reason: 'the rest of the identity is unchanged — only admin is',
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'the escalated token cannot do what a real admin token can',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          final victim = await db.authenticate(
            'users',
            const PasswordAuthPayload(
              email: 'victim@example.com',
              password: 'victim-password-1',
            ),
          );
          expect(victim, isNotNull);
          final victimId = victim!.user['id'] as String;

          final attacker = await db.authenticate(
            'users',
            const PasswordAuthPayload(
              email: 'attacker@example.com',
              password: 'attacker-password-1',
            ),
          );
          expect(attacker, isNotNull);

          final forged = _resign(
            attacker!.jwt,
            (payload) => payload
              ..['admin'] = <String, Object?>{'isAdmin': true, 'canEdit': true},
          );

          await expectLater(
            db.update(
              'users',
              UpdatePayload(
                where: Eq('id', victimId),
                updates: [
                  Update.object({'password': 'taken-over-1'}),
                ],
                jwt: forged,
              ),
            ),
            throwsA(anything),
            reason:
                "a self-escalated token must not be able to rewrite another "
                "user's password — the whole point of the escalation",
          );

          // Proof the refusal is about the escalation and not about the write
          // being impossible: a genuine admin token performs the same write.
          final admin = await db.authenticate(
            'admins',
            const PasswordAuthPayload(
              email: 'real-admin@example.com',
              password: 'real-admin-password-1',
            ),
          );
          expect(admin, isNotNull);

          await db.update(
            'users',
            UpdatePayload(
              where: Eq('id', victimId),
              updates: [
                Update.object({'password': 'admin-set-password-1'}),
              ],
              jwt: admin!.jwt,
            ),
          );

          expect(
            await db.authenticate(
              'users',
              const PasswordAuthPayload(
                email: 'victim@example.com',
                password: 'admin-set-password-1',
              ),
            ),
            isNotNull,
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a genuine admin token keeps its powers',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          final session = await db.authenticate(
            'admins',
            const PasswordAuthPayload(
              email: 'still-admin@example.com',
              password: 'still-admin-password-1',
            ),
          );
          expect(session, isNotNull);

          final parsed = await db.parseJwt(session!.jwt);
          expect(
            parsed!.admin.isAdmin,
            isTrue,
            reason:
                'the fix must re-derive admin, not remove it — `admins` mixes '
                'in AsAdmin, so its tokens stay admin',
          );
          expect(parsed.admin.canEdit, isTrue);
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    // An escalation attempt is a signing-key compromise, which nothing else
    // would report — but the warning has to be rare enough to be read. The
    // first draft compared the whole claim against the schema and therefore
    // fired on every ordinary user request, because `Jwt.fromJson` normalises
    // a non-admin token's `canEdit` to null while the schema reports false.
    test(
      'an escalation is logged, and an honest token logs nothing',
      () async {
        if (!_runningOnDartVm) return;

        final honestLogs = _LogCapture();
        await _withDb(settings, appConfig, logs: honestLogs, (db) async {
          final session = await db.authenticate(
            'users',
            const PasswordAuthPayload(
              email: 'quiet-user@example.com',
              password: 'quiet-user-password-1',
            ),
          );
          // Several ordinary authenticated calls, none of them admin.
          await db.parseJwt(session!.jwt);
          // A plain user cannot list the auth table, and that denial must not
          // be mistaken for a key compromise either — a refused ordinary
          // request is still ordinary. Swallow the access denial; the log
          // assertion below is the point.
          try {
            await db.list('users', ListPayload(where: null, jwt: session.jwt));
          } on Object {
            // expected: table-level access is admin-only here
          }
        });

        expect(
          honestLogs.text,
          isNot(contains('claims admin powers')),
          reason:
              'a plain user going about their business must not look like a '
              'key compromise — an alert that fires constantly is not read',
        );

        final forgedLogs = _LogCapture();
        await _withDb(settings, appConfig, logs: forgedLogs, (db) async {
          final session = await db.authenticate(
            'users',
            const PasswordAuthPayload(
              email: 'loud-user@example.com',
              password: 'loud-user-password-1',
            ),
          );
          await db.parseJwt(
            _resign(
              session!.jwt,
              (payload) => payload
                ..['admin'] = <String, Object?>{
                  'isAdmin': true,
                  'canEdit': true,
                },
            ),
          );
        });

        expect(
          forgedLogs.text,
          contains('claims admin powers'),
          reason: 'the one case worth waking someone for must be reported',
        );
        expect(forgedLogs.text, contains('rotate it'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    // The other direction, and the sharper test of the two: the live probe
    // found that flipping the flag to `false` made a real admin session *lose*
    // access, which is what proved the flag was being read from the token.
    // Now that it is derived, stripping it changes nothing.
    test(
      'stripping the admin claim from a real admin token changes nothing',
      () async {
        if (!_runningOnDartVm) return;

        await _withDb(settings, appConfig, (db) async {
          final session = await db.authenticate(
            'admins',
            const PasswordAuthPayload(
              email: 'demote-me@example.com',
              password: 'demote-me-password-1',
            ),
          );
          expect(session, isNotNull);

          final demoted = _resign(
            session!.jwt,
            (payload) => payload
              ..['admin'] = <String, Object?>{
                'isAdmin': false,
                'canEdit': false,
              },
          );
          final stripped = _resign(session.jwt, (payload) {
            payload.remove('admin');
            return payload;
          });

          for (final (label, token) in [
            ('flipped to false', demoted),
            ('removed entirely', stripped),
          ]) {
            final parsed = await db.parseJwt(token);
            expect(
              parsed!.admin.isAdmin,
              isTrue,
              reason:
                  'admin claim $label must not cost a real admin their powers — '
                  'the claim is not the source of truth any more',
            );
          }
        });
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

const _jwtSecret = 'jwt-admin-tamper-e2e-Ct7YbQ5nTz9KwMr2VxHd4CsLp8Ja';
const _passwordSecret = 'jwt-admin-tamper-e2e-pw-Zt4Rq8mNvXcB3wKdHs6yLpJ2';

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

/// Collects everything the server logs during a `_withDb` block.
class _LogCapture implements StreamConsumer<List<int>> {
  final _bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.forEach(_bytes.addAll);
  }

  @override
  Future<void> close() async {}

  String get text => utf8.decode(_bytes);
}

Future<void> _withDb(
  Settings settings,
  AppConfig appConfig,
  Future<void> Function(ZonaiDb db) body, {
  _LogCapture? logs,
}) async {
  late ZonaiDb db;
  await runMergedScopedFuture(
    () async {
      // The fixed resolver is honoured (`_run` prefers it over the config
      // worker), so the secret the server signs with is the one this file
      // forges with — otherwise a "rejected" token would prove nothing.
      db = ZonaiDb(configResolver: ConfigResolver.fixed(appConfig));
      try {
        await body(db);
      } finally {
        await db.dispose();
      }
    },
    override: {
      ..._e2eScopeOverrides(settings, appConfig: appConfig, logs: logs),
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
  _LogCapture? logs,
}) {
  return {
    fsProvider.overrideWith(LocalFileSystem.new),
    loggerProvider.overrideWith(
      () => logs == null
          ? Logger(level: .error)
          : Logger(
              level: .warning,
              stdout: IOSink(logs),
              stderr: IOSink(logs),
            ),
    ),
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
