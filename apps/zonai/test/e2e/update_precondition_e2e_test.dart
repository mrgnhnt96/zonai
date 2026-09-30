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

/// `expect` on an update: a precondition the target rows must meet, answered
/// with 412 and the current rows instead of a write when they do not.
///
/// Reuses the `e2e/data_plane_access_repro` fixture: `notes` is permissive at
/// both levels for a signed-in owner's writes, so the only thing refusing an
/// update here is the precondition under test.
void main() {
  group('update precondition e2e', () {
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

    Future<String> note(
      ZonaiDb db,
      String token,
      String title,
      String owner,
    ) async {
      final created = await db.create(
        'notes',
        CreatePayload(object: {'title': title, 'owner_id': owner}, jwt: token),
      );
      return '${created['id']}';
    }

    test('an update whose expect holds is applied', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        final me = await user(db, 'b3-holds@example.com');
        final token = await adminToken(db, 'admin-b3-holds@example.com');
        final id = await note(db, token, 'v1', me.id);

        final updated = await db.update(
          'notes',
          UpdatePayload(
            where: Eq('id', id),
            limit: 1,
            updates: [Update.column('title', .literal('v2'))],
            expect: const Eq('title', 'v1'),
            jwt: me.jwt,
          ),
        );

        expect(updated.single['title'], 'v2');
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('an update whose expect fails is refused with the current row, and '
        'writes nothing', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        final me = await user(db, 'b3-fails@example.com');
        final token = await adminToken(db, 'admin-b3-fails@example.com');
        final id = await note(db, token, 'v2', me.id);

        await expectLater(
          db.update(
            'notes',
            UpdatePayload(
              where: Eq('id', id),
              limit: 1,
              updates: [Update.column('title', .literal('v3'))],
              expect: const Eq('title', 'v1'),
              jwt: me.jwt,
            ),
          ),
          throwsA(
            isA<PreconditionFailedException>().having(
              (e) => e.current.map((r) => r['title']),
              'current titles',
              ['v2'],
            ),
          ),
        );

        final row = await db.read(
          'notes',
          ViewPayload(where: Eq('id', id), jwt: me.jwt),
        );
        expect(row['title'], 'v2');
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('a many-row update is refused whole when any target fails, and '
        'reports only the failing rows', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        final me = await user(db, 'b3-many@example.com');
        final token = await adminToken(db, 'admin-b3-many@example.com');
        await note(db, token, 'b3-many:ok', me.id);
        final stale = await note(db, token, 'b3-many:stale', me.id);

        await expectLater(
          db.update(
            'notes',
            UpdatePayload(
              where: const StartsWith('title', 'b3-many:'),
              updates: [Update.column('owner_id', .literal(me.id))],
              expect: const Eq('title', 'b3-many:ok'),
              jwt: me.jwt,
            ),
          ),
          throwsA(
            isA<PreconditionFailedException>().having(
              (e) => e.current.map((r) => r['id']),
              'current ids',
              [stale],
            ),
          ),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    // Review of #50: a caller who may UPDATE a row but not VIEW it gets the
    // 412 with nothing in it. Being allowed to write a row is not being
    // allowed to read it back.
    test(
      'a failing expect on a row the caller cannot view reports no rows',
      () async {
        if (!_runningOnDartVm) return;

        await withDb((db) async {
          final owner = await user(db, 'b3-hidden-owner@example.com');
          final other = await user(db, 'b3-hidden-other@example.com');
          final token = await adminToken(db, 'admin-b3-hidden@example.com');
          final id = await note(db, token, 'b3-hidden', owner.id);

          await expectLater(
            db.update(
              'notes',
              UpdatePayload(
                where: Eq('id', id),
                limit: 1,
                updates: [Update.column('title', .literal('x'))],
                expect: const Eq('title', 'not-it'),
                jwt: other.jwt,
              ),
            ),
            throwsA(
              isA<PreconditionFailedException>().having(
                (e) => e.current,
                'current',
                isEmpty,
              ),
            ),
          );
        });
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    // Review of #50: every 403 must win over a 412, or a refusal leaks that
    // the row exists and what it does not match.
    test('a rule denial wins over a failing expect', () async {
      if (!_runningOnDartVm) return;

      await withDb((db) async {
        final me = await user(db, 'b3-locked@example.com');
        final token = await adminToken(db, 'admin-b3-locked@example.com');
        final id = await note(db, token, 'locked', me.id);

        await expectLater(
          db.update(
            'notes',
            UpdatePayload(
              where: Eq('id', id),
              limit: 1,
              updates: [Update.column('title', .literal('x'))],
              expect: const Eq('title', 'not-it'),
              jwt: me.jwt,
            ),
          ),
          throwsA(isA<RowAccessDeniedException>()),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 5)));

    test(
      'control: no row matched is still an empty result, not a 412',
      () async {
        if (!_runningOnDartVm) return;

        await withDb((db) async {
          final me = await user(db, 'b3-none@example.com');

          final updated = await db.update(
            'notes',
            UpdatePayload(
              where: const Eq('id', 'no-such-note'),
              limit: 1,
              updates: [Update.column('title', .literal('x'))],
              expect: const Eq('title', 'v1'),
              jwt: me.jwt,
            ),
          );

          expect(updated, isEmpty);
        });
      },
      timeout: const Timeout(Duration(minutes: 5)),
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
