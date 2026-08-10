import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/project/project_runtime.dart';
import 'package:zonai/src/domain/settings.dart';

/// [projectResolvesZonai] decides whether `zonai build` compiles a
/// project-linked binary or falls back to worker IPC, and both answers look
/// like a successful build from outside -- a wrong `false` silently costs
/// in-process dispatch, a wrong `true` fails the compile. So each shape it
/// has to recognise gets a case here rather than only e2e coverage.
void main() {
  group('projectResolvesZonai', () {
    test('finds zonai beside the project', () {
      final fs = MemoryFileSystem();
      _writePackageConfig(fs, '/app', const ['zonai_schema', 'zonai']);

      expect(_resolveIn(fs, '/app'), isTrue);
    });

    test('reports a project that only depends on zonai_schema', () {
      final fs = MemoryFileSystem();
      _writePackageConfig(fs, '/app', const ['zonai_schema']);

      expect(_resolveIn(fs, '/app'), isFalse);
    });

    test('finds zonai in the workspace root config', () {
      // A pub workspace writes exactly one package_config.json, at the root:
      // members get none. Looking only beside the project's own pubspec
      // reported every workspace member -- apps/playground included -- as
      // unable to link, silently dropping in-process ops/rules.
      final fs = MemoryFileSystem();
      _writePackageConfig(fs, '/repo', const ['zonai_schema', 'zonai']);
      fs.directory('/repo/apps/server').createSync(recursive: true);

      expect(_resolveIn(fs, '/repo/apps/server'), isTrue);
    });

    test('stops at the nearest config rather than an ancestor', () {
      // A project with its own resolution is not a member of whatever
      // happens to sit above it; the ancestor answers a different question.
      final fs = MemoryFileSystem();
      _writePackageConfig(fs, '/repo', const ['zonai_schema', 'zonai']);
      _writePackageConfig(fs, '/repo/nested', const ['zonai_schema']);

      expect(_resolveIn(fs, '/repo/nested'), isFalse);
    });

    test('reports a project that was never resolved', () {
      final fs = MemoryFileSystem();
      fs.directory('/app').createSync(recursive: true);

      expect(_resolveIn(fs, '/app'), isFalse);
    });

    test('reports a half-written config instead of throwing', () {
      final fs = MemoryFileSystem();
      fs.directory('/app/.dart_tool').createSync(recursive: true);
      fs
          .file('/app/.dart_tool/package_config.json')
          .writeAsStringSync('{"configVersion":2,"packages":[{"name":"zon');

      expect(_resolveIn(fs, '/app'), isFalse);
    });
  });
}

bool _resolveIn(MemoryFileSystem fs, String projectRoot) {
  return runScoped(
    projectResolvesZonai,
    values: {
      fsProvider.overrideWith(() => fs),
      settingsProvider.overrideWith(() => _settingsAt(projectRoot)),
    },
  );
}

void _writePackageConfig(
  MemoryFileSystem fs,
  String root,
  List<String> packageNames,
) {
  fs.directory('$root/.dart_tool').createSync(recursive: true);
  final packages = packageNames
      .map(
        (name) =>
            '{"name":"$name","rootUri":"../../$name","packageUri":"lib/"}',
      )
      .join(',');
  fs
      .file('$root/.dart_tool/package_config.json')
      .writeAsStringSync('{"configVersion":2,"packages":[$packages]}');
}

Settings _settingsAt(String basePath) => Settings(
  basePath: basePath,
  path: 'zonai.yaml',
  migrationsPath: '.zonai/migrations',
  dataPath: '.zonai/data',
  schemasPath: 'lib/src/schemas',
  extensionsPath: 'lib/src/extensions',
  rulesPath: 'lib/src/rules',
  operationsPath: 'lib/src/operations',
  configPath: 'lib/src/config',
  emailTemplatesPath: 'lib/src/email_templates',
  rateLimitPath: 'lib/src/rate_limit',
  cronsPath: 'lib/src/crons',
  imagesPath: '.zonai/data/images',
  buildSettings: BuildSettings.current(),
  version: kVersion,
);
