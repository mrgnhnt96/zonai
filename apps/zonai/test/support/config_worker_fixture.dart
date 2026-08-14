import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zonai/gen/version.dart';

import 'package_roots.dart';
import 'temp_directory.dart';

/// A throwaway project with a compiled `db_config.exe`, for tests that
/// construct `ZonaiDb()` directly and need real JWT/config resolution.
///
/// `ZonaiDb._run` always re-overrides `configResolverProvider` with a real
/// `ConfigMailman`-backed resolver (see zonai_db.dart), so `ConfigResolver
/// .fixed(...)` never actually takes effect once a call goes through
/// `ZonaiDb` -- `ConfigMailman` unconditionally talks to whatever
/// `settings.compiledConfigPath` points at. The only way to make
/// `ZonaiDb().parseJwt(...)` (etc.) resolve a known secret is to give it a
/// real, compiled config worker to talk to.
class ConfigWorkerFixture {
  const ConfigWorkerFixture._(this.projectRoot);

  final Directory projectRoot;

  /// Path this fixture's `Settings` (loaded via `Settings.load(projectRoot
  /// .path)`, see the e2e tests for the same pattern) resolves
  /// `compiledConfigPath` to.
  String get compiledConfigPath =>
      p.join(projectRoot.path, '.zonai', 'executables', 'db_config.exe');

  /// Creates a project with just `lib/src/config/app_config.dart`
  /// (returning the given secrets) and compiles it -- `zonai compile`
  /// no-ops ("Compiled 0 X") for the other worker kinds since their source
  /// directories don't exist, so this only pays for what it needs.
  static Future<ConfigWorkerFixture> setUp({
    required String namePrefix,
    required String appName,
    required String passwordSecret,
    required String jwtSecret,
  }) async {
    final projectRoot = Directory.systemTemp.createTempSync(
      'zonai_${namePrefix}_',
    );

    Directory(
      p.join(projectRoot.path, 'lib', 'src', 'config'),
    ).createSync(recursive: true);

    File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: zonai_${namePrefix}_fixture
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  zonai_schema:
    path: ${jsonEncode(zonaiSchemaPackageRootFromConfig())}
''');

    File(p.join(projectRoot.path, 'zonai.yaml')).writeAsStringSync('''
version: $kVersion
configPath: lib/src/config
''');

    File(
      p.join(projectRoot.path, 'lib', 'src', 'config', 'app_config.dart'),
    ).writeAsStringSync('''
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: ${jsonEncode(appName)},
    passwordSecret: ${jsonEncode(passwordSecret)},
    jwtSecret: ${jsonEncode(jwtSecret)},
  );
}
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

    final zonaiEntry = p.normalize(
      p.join(Directory.current.path, 'bin', 'zonai.dart'),
    );
    final compile = await Process.run(Platform.resolvedExecutable, [
      'run',
      zonaiEntry,
      'compile',
      '--no-version-check',
      '--no-schema-version-check',
    ], workingDirectory: projectRoot.path);
    if (compile.exitCode != 0) {
      throw StateError(
        'zonai compile failed:\n${compile.stderr}\n${compile.stdout}',
      );
    }

    final fixture = ConfigWorkerFixture._(projectRoot);
    if (!File(fixture.compiledConfigPath).existsSync()) {
      throw StateError(
        'zonai compile must produce ${fixture.compiledConfigPath}',
      );
    }

    return fixture;
  }

  void tearDown() {
    deleteTempDirectory(projectRoot);
  }
}
