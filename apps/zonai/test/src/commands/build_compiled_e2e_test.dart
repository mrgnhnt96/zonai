import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:zonai/gen/version.dart';

import '../../support/raindrop_package_roots.dart';

/// End-to-end: a compiled `zonai` binary running `zonai build` against a
/// project targeting its own platform must bundle a working copy of
/// itself at `build/zonai`, not silently omit it.
void main() {
  group('compiled zonai build', () {
    late Directory projectRoot;
    late Directory zonaiPackageDir;
    late String executablePath;

    setUpAll(() async {
      if (!_runningOnDartVm) {
        return;
      }

      zonaiPackageDir = Directory(zonaiPackageRootFromConfig());
      final raindropPackages = RaindropPackageRoots.fromPackageConfig();

      projectRoot = Directory.systemTemp.createTempSync('zonai_build_e2e_');
      executablePath = p.join(projectRoot.path, 'zonai');

      await _bootstrapEndUserProject(
        projectRoot: projectRoot,
        raindropRoot: raindropPackages.raindrop,
        raindropSqliteRoot: raindropPackages.raindropSqlite,
        resqliteRoot: raindropPackages.resqlite,
      );

      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'exe',
        '-D__ZONAI_COMPILED__=true',
        'bin/zonai.dart',
        '-o',
        executablePath,
      ], workingDirectory: zonaiPackageDir.path);
      if (compile.exitCode != 0) {
        throw StateError(
          'dart compile exe failed:\n${compile.stderr}\n${compile.stdout}',
        );
      }
    });

    tearDownAll(() {
      projectRoot.deleteSync(recursive: true);
    });

    test(
      'bundles a working copy of itself at build/zonai',
      () async {
        if (!_runningOnDartVm) {
          return;
        }

        final result = await Process.run(executablePath, [
          'build',
          '--no-version-check',
        ], workingDirectory: projectRoot.path);

        expect(
          result.exitCode,
          0,
          reason: '${result.stderr}\n${result.stdout}',
        );

        final bundledExecutable = File(
          p.join(projectRoot.path, 'build', 'zonai'),
        );
        expect(
          bundledExecutable.existsSync(),
          isTrue,
          reason:
              'zonai build must copy the running binary into build/zonai '
              'so the bundle is self-contained',
        );

        final version = await Process.run(bundledExecutable.path, [
          'version',
          '--no-version-check',
        ]);
        expect(
          version.exitCode,
          0,
          reason:
              'bundled build/zonai must itself run: '
              '${version.stderr}\n${version.stdout}',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'copies migration SQL into the bundle with its contents intact',
      () async {
        if (!_runningOnDartVm) {
          return;
        }

        final generate = await Process.run(executablePath, [
          'db',
          'migrate',
          'generate',
          '--name',
          'initialize',
          '--no-version-check',
        ], workingDirectory: projectRoot.path);
        expect(
          generate.exitCode,
          0,
          reason: '${generate.stderr}\n${generate.stdout}',
        );

        final sourceMigration = File(
          p.join(
            projectRoot.path,
            '.zonai',
            'migrations',
            '0000_initialize.sql',
          ),
        );
        expect(
          sourceMigration.existsSync(),
          isTrue,
          reason: 'db migrate generate must produce a migration file',
        );
        final sourceSql = sourceMigration.readAsStringSync();
        expect(
          sourceSql,
          isNotEmpty,
          reason: 'generated migration should contain the users CREATE TABLE',
        );

        final build = await Process.run(executablePath, [
          'build',
          '--no-version-check',
        ], workingDirectory: projectRoot.path);
        expect(build.exitCode, 0, reason: '${build.stderr}\n${build.stdout}');

        final bundledMigration = File(
          p.join(
            projectRoot.path,
            'build',
            '.zonai',
            'migrations',
            '0000_initialize.sql',
          ),
        );
        expect(
          bundledMigration.existsSync(),
          isTrue,
          reason:
              'zonai build must copy migrations into build/.zonai/migrations',
        );
        expect(
          bundledMigration.readAsStringSync(),
          sourceSql,
          reason:
              'zonai build must await the migration file write -- a bundle '
              'with an empty migration file breaks every deploy that '
              'relies on it (fails with "no such table" at runtime)',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

Future<void> _bootstrapEndUserProject({
  required Directory projectRoot,
  required String raindropRoot,
  required String raindropSqliteRoot,
  required String resqliteRoot,
}) async {
  Directory(
    p.join(projectRoot.path, 'lib', 'src', 'schemas'),
  ).createSync(recursive: true);

  File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: build_compiled_e2e_fixture
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  raindrop:
    path: ${jsonEncode(raindropRoot)}
  raindrop_sqlite:
    path: ${jsonEncode(raindropSqliteRoot)}

dependency_overrides:
  raindrop:
    path: ${jsonEncode(raindropRoot)}
  resqlite:
    path: ${jsonEncode(resqliteRoot)}
''');

  File(p.join(projectRoot.path, 'zonai.yaml')).writeAsStringSync('''
version: $kVersion
migrationsPath: .zonai/migrations
schemasPath: lib/src/schemas
''');

  File(
    p.join(projectRoot.path, 'lib', 'src', 'schemas', 'users.dart'),
  ).writeAsStringSync('''
import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

class User {
  const User({required this.name, this.id});

  final int? id;
  final String name;
}

class UserSchema extends Schema<User> {
  UserSchema(super.\$)
      : id = \$.integer('id', (s) => s.id).primaryKey(autoIncrement: true),
        name = \$.text('name', (s) => s.name);

  @override
  User fromRow(RowReader read) => User(
        id: read(id),
        name: read(name),
      );

  final ColumnType<int?> id;
  final ColumnType<String> name;
}

final users = sqliteTable('users', UserSchema.new);
''');

  final pubGet = await Process.run(Platform.resolvedExecutable, const [
    'pub',
    'get',
  ], workingDirectory: projectRoot.path);
  if (pubGet.exitCode != 0) {
    throw StateError(
      'dart pub get failed:\n${pubGet.stderr}\n${pubGet.stdout}',
    );
  }
}
