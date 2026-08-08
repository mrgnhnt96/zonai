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

/// Reproduces the "parallel /db/list requests intermittently 500" report:
/// firing several list requests at once against a live server reliably
/// produced intermittent failures, while the same requests run sequentially
/// always succeeded.
void main() {
  group('concurrent /db/list e2e', () {
    late Directory projectRoot;
    late Directory fixtureRoot;
    late Settings settings;

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
            'concurrency_repro',
          ),
        ),
      );
      if (!fixtureRoot.existsSync()) {
        fixtureRoot = Directory(p.normalize('e2e/concurrency_repro'));
      }
      expect(
        fixtureRoot.existsSync(),
        isTrue,
        reason: 'fixture missing at ${fixtureRoot.path}',
      );

      projectRoot = Directory.systemTemp.createTempSync(
        'zonai_concurrency_e2e_',
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
      projectRoot.deleteSync(recursive: true);
    });

    test(
      'many concurrent list() calls against one ZonaiDb all succeed',
      () async {
        if (!_runningOnDartVm) {
          return;
        }

        await runMergedScopedFuture(() async {
          final db = ZonaiDb();
          try {
            for (var i = 0; i < 20; i++) {
              await db.create(
                'items',
                CreatePayload(object: {'name': 'item_$i'}),
              );
            }

            final errors = <Object>[];
            for (var round = 0; round < 5; round++) {
              final results = await Future.wait(
                List.generate(
                  20,
                  (_) => db
                      .list('items', ListPayload(where: null))
                      .then<Object?>((r) => null)
                      .catchError((Object e) => e),
                ),
              );
              errors.addAll(results.whereType<Object>());
            }

            expect(
              errors,
              isEmpty,
              reason: 'concurrent list() calls failed: $errors',
            );
          } finally {
            await db.dispose();
          }
        }, override: _e2eScopeOverrides(settings));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

Set<ScopedRef<dynamic>> _e2eScopeOverrides(Settings settings) {
  return {
    fsProvider.overrideWith(LocalFileSystem.new),
    loggerProvider.overrideWith(() => Logger(level: .error)),
    settingsProvider.overrideWith(() => settings),
    processProvider,
    migrateProvider,
    mutationsProvider,
    cleanUpProvider,
    executableStopProvider,
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
name: zonai_concurrency_repro
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
