import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:zonai/gen/version.dart';

import '../../support/package_roots.dart';
import '../../support/temp_directory.dart';

/// End-to-end: compiled zonai generates migrations when raindrop_cli is not
/// on disk (typical end-user project layout).
void main() {
  group('compiled migrate generate', () {
    late Directory projectRoot;
    late Directory zonaiPackageDir;
    late String executablePath;

    setUpAll(() async {
      if (!_runningOnDartVm) {
        return;
      }

      zonaiPackageDir = Directory(zonaiPackageRootFromConfig());

      projectRoot = createCanonicalTempSync('zonai_migrate_e2e_');
      executablePath = p.join(projectRoot.path, 'zonai-test');

      await _bootstrapEndUserProject(
        projectRoot: projectRoot,
        zonaiSchemaRoot: zonaiSchemaPackageRootFromConfig(),
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
      deleteTempDirectory(projectRoot);
    });

    test('generates SQL when raindrop_cli is not in package_config', () async {
      if (!_runningOnDartVm) {
        return;
      }

      final config =
          jsonDecode(
                File(
                  p.join(projectRoot.path, '.dart_tool', 'package_config.json'),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final packageNames = (config['packages'] as List<dynamic>).map(
        (pkg) => (pkg as Map<String, dynamic>)['name'] as String,
      );
      expect(packageNames, isNot(contains('raindrop_cli')));

      final migrationsDir = Directory(
        p.join(projectRoot.path, '.zonai', 'migrations'),
      );
      if (migrationsDir.existsSync()) {
        migrationsDir.deleteSync(recursive: true);
      }

      final result = await Process.run(executablePath, [
        'db',
        'migrate',
        'generate',
        '--name',
        'initialize',
        '--no-version-check',
        '--no-schema-version-check',
      ], workingDirectory: projectRoot.path);

      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      expect(
        '${result.stdout}',
        contains('Generated migrations'),
        reason: '${result.stderr}',
      );
      expect(migrationsDir.existsSync(), isTrue);

      final sqlFiles = migrationsDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.sql'))
          .toList();
      expect(sqlFiles, isNotEmpty);

      final sql = sqlFiles.first.readAsStringSync();
      expect(sql, contains('CREATE TABLE'));
      expect(sql, contains('users'));

      final materializedHost = File(
        p.join(
          projectRoot.path,
          '.dart_tool',
          'raindrop',
          'ddl_subprocess_host.dart',
        ),
      );
      expect(
        materializedHost.existsSync(),
        isTrue,
        reason: 'compiled migrate should materialize ddl_subprocess_host.dart',
      );
    });
  });
}

bool get _runningOnDartVm =>
    p.basename(Platform.resolvedExecutable).toLowerCase().startsWith('dart');

Future<void> _bootstrapEndUserProject({
  required Directory projectRoot,
  required String zonaiSchemaRoot,
}) async {
  Directory(
    p.join(projectRoot.path, 'lib', 'src', 'schemas'),
  ).createSync(recursive: true);

  File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: migrate_compiled_e2e_fixture
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaRoot)}
''');

  File(p.join(projectRoot.path, 'zonai.yaml')).writeAsStringSync('''
version: $kVersion
migrationsPath: .zonai/migrations
schemasPath: lib/src/schemas
''');

  File(
    p.join(projectRoot.path, 'lib', 'src', 'schemas', 'users.dart'),
  ).writeAsStringSync('''
import 'package:zonai_schema/zonai_schema.dart';

class User {
  const User({required this.name, this.id});

  final int? id;
  final String name;
}

class UserSchema extends Table<User> {
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

final users = table('users', UserSchema.new);
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
