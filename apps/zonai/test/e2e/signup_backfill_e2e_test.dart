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

/// Reproduces the "onSignUp hook backfill silently never persists" report:
/// a hook that reads a pending invite and queues a `mutate.update.one` write
/// during `AuthExtension.onSignUp` runs (and can read data) but the queued
/// write is dropped because sign-up never drains the queued effects, unlike
/// every other auth extension step (sign-in, refresh, logout, password
/// reset, external-auth provisioning).
void main() {
  group('signup backfill e2e', () {
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
            'signup_backfill_repro',
          ),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/signup_backfill_repro'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = Directory.systemTemp.createTempSync(
        'zonai_signup_backfill_e2e_',
      );
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
        appName: 'Signup Backfill E2E',
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

    test(
      'onSignUp hook write to another table is persisted after sign-up',
      () async {
        if (!_runningOnDartVm) {
          return;
        }

        late ZonaiDb db;
        await runMergedScopedFuture(
          () async {
            db = ZonaiDb();
            try {
              const email = 'sam@example.com';

              await db.create(
                'invites',
                const CreatePayload(object: {'email': email}),
              );

              final auth = await db.authenticate(
                'users',
                const PasswordAuthPayload(email: email, password: 'hunter22'),
              );
              expect(auth, isNotNull);
              final userId = auth!.user['id'];
              expect(userId, isNotNull);

              final invites = await db.list(
                'invites',
                ListPayload(where: Eq('email', email)),
              );

              expect(invites.items, hasLength(1));
              expect(
                invites.items.single['user_id'],
                userId,
                reason:
                    'the onSignUp hook queued a mutate.update.one to backfill '
                    "the invite's user_id, but sign-up never drains queued "
                    'effects, so the write is silently dropped',
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
      },
      timeout: const Timeout(Duration(minutes: 2)),
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
name: zonai_signup_backfill_repro
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
