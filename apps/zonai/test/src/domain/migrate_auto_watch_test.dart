import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/package_roots.dart';
import '../../support/temp_directory.dart';

/// Regression test for the dev-server's "auto migration" file watcher.
///
/// It used to watch `.zonai/migrations` (the CLI's own output directory)
/// instead of the schemas directory, so editing schema files never triggered
/// a regenerate. On top of that, concurrent watcher events were dropped
/// instead of queuing a follow-up run, so a multi-table change made close
/// together could lose some of the tables.
///
/// [Migrate] is driven for real, out-of-process, via
/// `migrate_auto_watch_harness.dart`: `raindrop_cli` resolves the owning
/// project for schema introspection from `Directory.current`, and this
/// package (`apps/zonai`) has its own `raindrop.yaml` for its internal db —
/// mutating this test's own working directory would risk that config
/// clobbering real generated files, so the harness runs in a disposable
/// fixture project instead.
void main() {
  group('Migrate.auto', () {
    late Directory projectRoot;
    late Directory schemasDir;
    late Directory migrationsDir;
    late Process harness;

    setUpAll(() async {
      projectRoot = createCanonicalTempSync('zonai_migrate_auto_watch_');
      schemasDir = Directory(p.join(projectRoot.path, 'lib', 'src', 'schemas'))
        ..createSync(recursive: true);
      // `auto()` only runs its `initialize` migration when the migrations
      // dir doesn't already exist yet, so leave it uncreated.
      migrationsDir = Directory(
        p.join(projectRoot.path, '.zonai', 'migrations'),
      );

      File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: migrate_auto_watch_fixture
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaPackageRootFromConfig())}
''');

      File(p.join(schemasDir.path, 'users.dart')).writeAsStringSync(
        _tableSchemaSource(className: 'UserSchema', tableName: 'users'),
      );

      final pubGet = await Process.run(Platform.resolvedExecutable, const [
        'pub',
        'get',
      ], workingDirectory: projectRoot.path);
      if (pubGet.exitCode != 0) {
        throw StateError(
          'dart pub get failed:\n${pubGet.stderr}\n${pubGet.stdout}',
        );
      }

      final harnessPath = p.join(
        zonaiPackageRootFromConfig(),
        'test',
        'support',
        'migrate_auto_watch_harness.dart',
      );

      harness = await Process.start(Platform.resolvedExecutable, [
        'run',
        harnessPath,
        schemasDir.path,
        migrationsDir.path,
      ], workingDirectory: projectRoot.path);
      harness.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => printOnFailure('[harness stderr] $line'));

      final ready = Completer<void>();
      harness.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.trim() == 'READY' && !ready.isCompleted) {
              ready.complete();
            }
          });
      // 90s, not 30s -- see migrate_config_isolation_test.dart for the measurement.
      // Same spawn-and-wait-for-READY shape, same starvation exposure.
      await ready.future.timeout(const Duration(seconds: 90));
    });

    tearDownAll(() {
      harness.kill();
      // Not deleteSync: harness.kill() has just asked a child process to go
      // away and Windows will not unlink a directory it still has a handle
      // into, so this raced and failed teardown after every assertion passed
      // ("The process cannot access the file because it is being used by
      // another process", errno 32, run 31853443536).
      deleteTempDirectory(projectRoot);
    });

    test(
      'reacts to schema edits and captures a multi-table burst',
      () async {
        // The first run pays for a cold analyzer/analysis-context start
        // (plus a runtime-introspection subprocess), which can take a while.
        await _waitUntil(
          () =>
              _allMigrationSql(migrationsDir).contains('CREATE TABLE "users"'),
          reason: 'initial migration for the pre-existing schema',
          timeout: const Duration(seconds: 90),
        );

        // Simulate a multi-table change: several schema files landing on
        // disk close together, the way an editor's "save all" or a git
        // checkout would deliver them.
        File(p.join(schemasDir.path, 'posts.dart')).writeAsStringSync(
          _tableSchemaSource(className: 'PostSchema', tableName: 'posts'),
        );
        File(p.join(schemasDir.path, 'comments.dart')).writeAsStringSync(
          _tableSchemaSource(className: 'CommentSchema', tableName: 'comments'),
        );

        await _waitUntil(
          () =>
              _allMigrationSql(
                migrationsDir,
              ).contains('CREATE TABLE "posts"') &&
              _allMigrationSql(
                migrationsDir,
              ).contains('CREATE TABLE "comments"'),
          reason: 'migrations for both tables from the close-together edit',
          timeout: const Duration(seconds: 60),
        );
      },
      // Outer budget stays the sum of the inner waits: 90 + 90 + 60.
      timeout: const Timeout(Duration(minutes: 4)),
    );
  });
}

String _tableSchemaSource({
  required String className,
  required String tableName,
}) {
  return '''
import 'package:zonai_schema/zonai_schema.dart';

class ${className}Row {
  const ${className}Row({required this.name, this.id});

  final int? id;
  final String name;
}

class $className extends Table<${className}Row> {
  $className(super.\$)
      : id = \$.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
        name = \$.text('name', (s) => s.name);

  @override
  ${className}Row fromRow(RowReader read) => ${className}Row(
        id: read(id),
        name: read(name),
      );

  final ColumnType<int?> id;
  final ColumnType<String> name;
}

final $tableName = table('$tableName', $className.new);
''';
}

String _allMigrationSql(Directory migrationsDir) {
  if (!migrationsDir.existsSync()) return '';
  final sqlFiles = migrationsDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.sql'))
      .toList();
  return sqlFiles.map((file) => file.readAsStringSync()).join('\n');
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for: $reason');
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
}
