import 'dart:async';
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

/// `$.revision`: a column the server maintains -- 0 on create, one higher on
/// every update -- and refuses to let a client write.
///
/// Reuses the `e2e/data_plane_access_repro` fixture, whose `notes` table
/// carries a `rev` column.
void main() {
  group('revision column e2e', () {
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
            'data_plane_access_repro',
          ),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/data_plane_access_repro'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_data_plane_access_e2e_');
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
        appName: 'Data Plane Access E2E',
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
      deleteTempDirectory(projectRoot);
    });

    Future<void> withDb(Future<void> Function(ZonaiDb db) body) async {
      late ZonaiDb db;
      await runMergedScopedFuture(
        () async {
          db = ZonaiDb();
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

    /// An admin token — `admins` is `AsAdmin`, so this is `isAdmin`/`canEdit`,
    /// the most privileged reader the data plane recognises.
    Future<String> adminToken(ZonaiDb db, String email) async {
      final signUp = await db.authenticate(
        'admins',
        PasswordAuthPayload(email: email, password: 'admin-password-1'),
      );
      expect(signUp, isNotNull);
      return signUp!.jwt;
    }

    Future<({String jwt, String id})> user(ZonaiDb db, String email) async {
      final signUp = await db.authenticate(
        'users',
        PasswordAuthPayload(email: email, password: 'user-password-1'),
      );
      expect(signUp, isNotNull);
      final id = signUp!.user['id'];
      expect(id, isNotNull);
      return (jwt: signUp.jwt, id: '$id');
    }

    Future<Map<String, Object?>> note(ZonaiDb db, String token, String owner) =>
        db.create(
          'notes',
          CreatePayload(object: {'title': 'r', 'owner_id': owner}, jwt: token),
        );

    test('a create returns revision 0', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        final me = await user(db, 'rev-create@example.com');
        final token = await adminToken(db, 'admin-rev-create@example.com');

        expect((await note(db, token, me.id))['rev'], 0);
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('every update increments it, and reads return it', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        final me = await user(db, 'rev-update@example.com');
        final token = await adminToken(db, 'admin-rev-update@example.com');
        final id = '${(await note(db, token, me.id))['id']}';

        for (final expected in [1, 2]) {
          final updated = await db.update(
            'notes',
            UpdatePayload(
              where: Eq('id', id),
              limit: 1,
              updates: [Update.column('title', .literal('r$expected'))],
              jwt: me.jwt,
            ),
          );
          expect(updated.single['rev'], expected);
        }

        final read = await db.read(
          'notes',
          ViewPayload(where: Eq('id', id), jwt: me.jwt),
        );
        expect(read['rev'], 2);

        final listed = await db.list(
          'notes',
          ListPayload(where: Eq('id', id), jwt: me.jwt),
        );
        expect(listed.items.single['rev'], 2);
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('a client write to it is refused, on update and on create', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        final me = await user(db, 'rev-refuse@example.com');
        final token = await adminToken(db, 'admin-rev-refuse@example.com');
        final id = '${(await note(db, token, me.id))['id']}';

        await expectLater(
          db.update(
            'notes',
            UpdatePayload(
              where: Eq('id', id),
              limit: 1,
              updates: [Update.column('rev', .literal(9))],
              jwt: me.jwt,
            ),
          ),
          throwsA(isA<ServerManagedColumnWriteException>()),
        );

        await expectLater(
          db.create(
            'notes',
            CreatePayload(
              object: {'title': 'r', 'owner_id': me.id, 'rev': 9},
              jwt: token,
            ),
          ),
          throwsA(isA<ServerManagedColumnWriteException>()),
        );

        final read = await db.read(
          'notes',
          ViewPayload(where: Eq('id', id), jwt: me.jwt),
        );
        expect(read['rev'], 0, reason: 'the refused update wrote nothing');
      });
    }, timeout: const Timeout(Duration(minutes: 5)));
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
  final result = await runZonaiCli(
    args,
    workingDirectory: projectRoot.path,
    environment: _forceWorkersEnv,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
}

/// See the note in `admin_password_update_e2e_test.dart`: the fixture depends
/// only on `zonai_schema`, so it cannot JIT-link a project-linked entry.
const _forceWorkersEnv = {'ZONAI_FORCE_WORKERS': '1'};

void _rewritePubspecPaths({
  required Directory projectRoot,
  required Directory repoRoot,
}) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  final zonaiSchemaRoot = p.join(repoRoot.path, 'libs', 'zonai_schema');
  pubspec.writeAsStringSync('''
name: zonai_data_plane_access_repro
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
