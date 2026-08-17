import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/zonai_schema.dart';
import '../support/temp_directory.dart';

/// End-to-end: a Supabase-shaped HS256 JWT is verified, provisions a user
/// via [AuthExtension.onExternalAuthFirstSeen], and resolves [Jwt.user].
void main() {
  group('external auth provisioning e2e', () {
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
          p.join(Directory.current.path, '..', '..', 'e2e', 'external_auth'),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        // When tests run from repo root via workspace tooling.
        fixtureRoot = Directory(p.normalize('e2e/external_auth'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_external_auth_e2e_');
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
        appName: 'External Auth E2E',
        passwordSecret: 'e2e-password-pepper-UVIjjOrrfaPgnBBY9JSAeTV3jaXjz1ky',
        jwtSecret: 'e2e-zonai-jwt-secret-8q4KsoOw8bJzuesZfcwzkhjSsCLsll1',
        baseUrl: 'http://localhost:8080',
        externalIdps: const [
          SharedSecretIdpConfig(
            issuer: 'https://abcdefgh.supabase.co/auth/v1',
            audience: 'authenticated',
            authTable: 'users',
            secret: 'e2e-supabase-jwt-secret',
          ),
        ],
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
      deleteTempDirectory(projectRoot);
    });

    test(
      'first-seen Supabase JWT provisions user and returns populated Jwt',
      () async {
        if (!_runningOnDartVm) {
          return;
        }

        const supabaseSecret = 'e2e-supabase-jwt-secret';
        const sub = '550e8400-e29b-41d4-a716-446655440000';
        final now = DateTime.utc(2026, 6, 18, 12, 0, 0);
        final token = _supabaseJwt(
          secret: supabaseSecret,
          sub: sub,
          email: 'sam@example.com',
          exp: now.add(const Duration(hours: 1)),
        );

        await withClock(Clock.fixed(now), () async {
          await runMergedScopedFuture(() async {
            final db = ZonaiDb();
            try {
              final jwt = await db.parseJwt(token);
              expect(jwt, isNotNull);
              expect(jwt!.userId.value, sub);
              expect(jwt.table, 'users');
              expect(jwt.user['id'], sub);
              expect(jwt.user['email'], 'sam@example.com');
            } finally {
              await db.dispose();
            }
          }, override: _e2eScopeOverrides(settings, appConfig: appConfig));
        });
      },
    );

    test(
      'second request with same sub reuses existing row without re-provisioning',
      () async {
        if (!_runningOnDartVm) {
          return;
        }

        const supabaseSecret = 'e2e-supabase-jwt-secret';
        const sub = '550e8400-e29b-41d4-a716-446655440000';
        final now = DateTime.utc(2026, 6, 18, 12, 5, 0);
        final token = _supabaseJwt(
          secret: supabaseSecret,
          sub: sub,
          email: 'sam@example.com',
          exp: now.add(const Duration(hours: 1)),
        );

        await withClock(Clock.fixed(now), () async {
          await runMergedScopedFuture(() async {
            final db = ZonaiDb();
            try {
              final jwt = await db.parseJwt(token);
              expect(jwt, isNotNull);
              expect(jwt!.user['email'], 'sam@example.com');
            } finally {
              await db.dispose();
            }
          }, override: _e2eScopeOverrides(settings, appConfig: appConfig));
        });
      },
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
name: zonai_external_auth_e2e
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

String _supabaseJwt({
  required String secret,
  required String sub,
  required String email,
  required DateTime exp,
}) {
  final expSecs = exp.millisecondsSinceEpoch ~/ 1000;
  final header = const {'alg': 'HS256', 'typ': 'JWT'};
  final payload = {
    'iss': 'https://abcdefgh.supabase.co/auth/v1',
    'aud': 'authenticated',
    'sub': sub,
    'email': email,
    'role': 'authenticated',
    'exp': expSecs,
  };
  return _signedHs256(secret: secret, header: header, payload: payload);
}

String _signedHs256({
  required String secret,
  required Map<String, Object?> header,
  required Map<String, Object?> payload,
}) {
  final h = base64Url
      .encode(utf8.encode(jsonEncode(header)))
      .replaceAll('=', '');
  final p = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  final signingInput = '$h.$p';
  final mac = Hmac(sha256, utf8.encode(secret));
  final sig = base64Url
      .encode(mac.convert(utf8.encode(signingInput)).bytes)
      .replaceAll('=', '');
  return '$signingInput.$sig';
}
