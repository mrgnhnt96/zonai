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

/// `POST /db/many` through a compiled operations worker.
///
/// A create-many travels to the worker as `operation: 'create'`, the same as
/// a single create, and the worker used to rebuild it as a single create.
/// That read the absent `object` and threw, so every create-many to a table
/// with a `TableOperations` class answered 500 ("Invalid request payload"),
/// while a single create to the same table worked. `widgets` in
/// `e2e/crud_matrix` has one (`WidgetOperations`).
///
/// It only shows through a real worker. A project that depends on `zonai`
/// links operations in-process and never serializes the request, which is why
/// nothing caught it (see `e2e/crud_matrix/pubspec.yaml`).
void main() {
  group('create-many through the operations worker e2e', () {
    late Directory projectRoot;
    late Directory fixtureRoot;
    late Settings settings;
    late AppConfig appConfig;

    /// Runs [body] with a live [ZonaiDb] against the migrated fixture.
    Future<T> withDb<T>(Future<T> Function(ZonaiDb db) body) async {
      late ZonaiDb db;
      return await runMergedScopedFuture(
        () async {
          db = ZonaiDb();
          try {
            return await body(db);
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

    setUpAll(() async {
      if (!_runningOnDartVm) {
        return;
      }

      fixtureRoot = Directory(
        p.normalize(
          p.join(Directory.current.path, '..', '..', 'e2e', 'crud_matrix'),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/crud_matrix'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = createCanonicalTempSync('zonai_create_many_e2e_');
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
      // Matches the fixture's lib/src/config/app_config.dart.
      appConfig = const AppConfig(
        appName: 'Zonai CRUD Matrix',
        passwordSecret:
            'crud-matrix-password-pepper-KW3PvuKi9E7Kk4ayngZT2DmjSrtbCKn',
        jwtSecret: 'crud-matrix-jwt-secret-W1ICKTqJEEH3bdfxL4EY5Ahnc7HnaM',
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
      if (!_runningOnDartVm) {
        return;
      }
      deleteTempDirectory(projectRoot);
    });

    Map<String, Object?> widget(String code) => {
      'code': code,
      'status': 'new',
      'quantity': 1,
      'weight': 1.5,
      'active': true,
    };

    test('a create-many writes every row', () async {
      if (!_runningOnDartVm) {
        return;
      }

      await withDb((db) async {
        final created = await db.createMany(
          'widgets',
          CreateManyPayload(objects: [widget('many-1'), widget('many-2')]),
        );

        expect(
          created.map((row) => row['code']),
          unorderedEquals(['many-1', 'many-2']),
        );

        final rows = await db.list(
          'widgets',
          ListPayload(where: In('code', ['many-1', 'many-2'])),
        );
        expect(
          rows.items.map((row) => row['code']),
          unorderedEquals(['many-1', 'many-2']),
        );
      });
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a single create to the same table still works', () async {
      if (!_runningOnDartVm) {
        return;
      }

      await withDb((db) async {
        final created = await db.create(
          'widgets',
          CreatePayload(object: widget('single-1')),
        );
        expect(created['code'], 'single-1');
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
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
name: zonai_crud_matrix
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
