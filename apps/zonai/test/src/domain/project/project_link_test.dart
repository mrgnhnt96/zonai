import 'dart:convert';

import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/project/project_link.dart';
import 'package:zonai/src/domain/settings.dart';

/// [resolveProjectLink] is the single decision behind `zonai build`, the dev
/// `serve`/`db`/`dev` re-exec, and the `--release` project binary: link the
/// project's ops and rules into the binary, or fall back to worker IPC.
///
/// Nothing observable fails when it answers wrong. Worker IPC *works*, so a
/// spurious skip costs in-process dispatch -- and per-operation rate limiting
/// with it -- while every build stays green and every deploy stays up. A
/// spurious link is the loud direction: the compile fails. So the quiet
/// direction is what most of these cases are about.
void main() {
  group('resolveProjectLink', () {
    test('uses the project\'s own resolution when it already has zonai', () {
      // apps/playground, and any project carrying `zonai: {path: ...}`.
      // Merging here would be a chance to get right something that is already
      // right, so the link carries no `--packages` at all.
      final fs = MemoryFileSystem();
      _writePackageConfig(fs, '/app', const ['zonai_schema', 'zonai']);

      final link = _resolve(
        fs,
        '/app',
        zonaiConfig: '/monorepo/.dart_tool/package_config.json',
      );

      expect(link.canLink, isTrue);
      expect(link.packageConfigPath, isNull);
      expect(link.overridden, isEmpty);
    });

    test(
      'merges zonai\'s graph in for a project that does not depend on it',
      () {
        // The case the whole file exists for: every real project. Before this,
        // it was an unconditional skip.
        final fs = MemoryFileSystem();
        _writePackageConfig(fs, '/app', const ['zonai_schema']);
        _writePackageConfig(fs, '/monorepo', const ['zonai', 'zonai_schema']);

        final link = _resolve(
          fs,
          '/app',
          zonaiConfig: '/monorepo/.dart_tool/package_config.json',
        );

        expect(link.canLink, isTrue);
        expect(
          link.packageConfigPath,
          '/app/.dart_tool/zonai/package_config.json',
        );

        // The merged config is the only reason the compile can resolve
        // `package:zonai/src/bootstrap.dart`; a link that reports success
        // without zonai in the file it points at is the failure this replaces.
        expect(_packageNames(fs, link.packageConfigPath!), contains('zonai'));
      },
    );

    test('reports the packages zonai\'s graph took over', () {
      // Returned so a caller can say it out loud: each of these is a package
      // the app's own code is now compiled against a version pub did not pick
      // for it. See logOverriddenPackages.
      final fs = MemoryFileSystem();
      _writePackageConfig(fs, '/app', const [
        'zonai_schema',
      ], root: 'file:///pub-cache');
      _writePackageConfig(fs, '/monorepo', const ['zonai', 'zonai_schema']);

      final link = _resolve(
        fs,
        '/app',
        zonaiConfig: '/monorepo/.dart_tool/package_config.json',
      );

      expect(link.overridden, ['zonai_schema']);
    });

    test('skips when zonai\'s own sources are not on disk', () {
      // The bare released binary on a deploy machine: nothing to merge with,
      // and no way around it. The limitation does not go away -- it just
      // stops being the only outcome.
      final fs = MemoryFileSystem();
      _writePackageConfig(fs, '/app', const ['zonai_schema']);

      final link = _resolve(fs, '/app', zonaiConfig: null);

      expect(link.canLink, isFalse);
      expect(link.skipReason, contains('not on disk'));
    });

    test('skips a project pub has never resolved', () {
      final fs = MemoryFileSystem();
      fs.directory('/app').createSync(recursive: true);

      final link = _resolve(
        fs,
        '/app',
        zonaiConfig: '/monorepo/.dart_tool/package_config.json',
      );

      expect(link.canLink, isFalse);
      expect(link.skipReason, contains('dart pub get'));
    });

    test('skips on a half-written config instead of throwing', () {
      final fs = MemoryFileSystem();
      fs.file('/app/.dart_tool/package_config.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"configVersion":2,"packages":[{"name":"zon');
      _writePackageConfig(fs, '/monorepo', const ['zonai']);

      final link = _resolve(
        fs,
        '/app',
        zonaiConfig: '/monorepo/.dart_tool/package_config.json',
      );

      expect(link.canLink, isFalse);
    });

    test('merges the workspace root config for a member project', () {
      // A pub workspace writes exactly one package config, at the root. The
      // project being built is very often a member directory with no
      // `.dart_tool` of its own, and the merged config still has to be written
      // beside *it* -- that is where the compile looks for the generated
      // entry.
      final fs = MemoryFileSystem();
      _writePackageConfig(fs, '/repo', const ['zonai_schema']);
      fs.directory('/repo/apps/server').createSync(recursive: true);
      _writePackageConfig(fs, '/monorepo', const ['zonai', 'zonai_schema']);

      final link = _resolve(
        fs,
        '/repo/apps/server',
        zonaiConfig: '/monorepo/.dart_tool/package_config.json',
      );

      expect(link.canLink, isTrue);
      expect(
        link.packageConfigPath,
        '/repo/apps/server/.dart_tool/zonai/package_config.json',
      );
      expect(_packageNames(fs, link.packageConfigPath!), contains('zonai'));
    });
  });

  group('projectPackageConfigPath', () {
    test('stops at the nearest config rather than an ancestor', () {
      final fs = MemoryFileSystem();
      _writePackageConfig(fs, '/repo', const ['zonai']);
      _writePackageConfig(fs, '/repo/nested', const ['zonai_schema']);

      expect(
        _run(fs, '/repo/nested', projectPackageConfigPath),
        '/repo/nested/.dart_tool/package_config.json',
      );
    });

    test('returns null when nothing above the project was ever resolved', () {
      final fs = MemoryFileSystem();
      fs.directory('/app').createSync(recursive: true);

      expect(_run(fs, '/app', projectPackageConfigPath), isNull);
    });
  });
}

ProjectLink _resolve(
  MemoryFileSystem fs,
  String projectRoot, {
  required String? zonaiConfig,
}) {
  return _run(
    fs,
    projectRoot,
    () => resolveProjectLink(findZonaiPackageConfig: () => zonaiConfig),
  );
}

T _run<T>(MemoryFileSystem fs, String projectRoot, T Function() body) {
  return runScoped(
    body,
    values: {
      fsProvider.overrideWith(() => fs),
      settingsProvider.overrideWith(() => _settingsAt(projectRoot)),
    },
  );
}

List<String> _packageNames(MemoryFileSystem fs, String configPath) {
  final config =
      json.decode(fs.file(configPath).readAsStringSync())
          as Map<String, Object?>;
  return [
    for (final p in config['packages'] as List) (p as Map)['name'] as String,
  ];
}

/// Writes a config whose packages all sit under [root], so two configs written
/// with different roots disagree on where a shared package lives -- which is
/// what makes an override an override.
void _writePackageConfig(
  MemoryFileSystem fs,
  String dir,
  List<String> packageNames, {
  String root = 'file:///monorepo/libs',
}) {
  fs.directory('$dir/.dart_tool').createSync(recursive: true);
  final packages = [
    for (final name in packageNames)
      {'name': name, 'rootUri': '$root/$name', 'packageUri': 'lib/'},
  ];
  fs
      .file('$dir/.dart_tool/package_config.json')
      .writeAsStringSync(
        json.encode({'configVersion': 2, 'packages': packages}),
      );
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
