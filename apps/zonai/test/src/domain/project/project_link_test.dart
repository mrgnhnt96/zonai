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

    test('skips when zonai\'s sources are present but not built', () {
      // The failure this exists to prevent is not a wrong answer, it is a
      // *hard* one: merging succeeds, the compile is told to use the merged
      // graph, and `dart compile exe` then dies on an import of a file that
      // was never generated -- with no fallback left, because the decision to
      // link had already been made. Every Verify Release build-command leg
      // failed exactly that way once linking started applying to projects
      // with no zonai dependency.
      final fs = MemoryFileSystem();
      _writePackageConfig(fs, '/app', const ['zonai_schema']);
      _writePackageConfig(fs, '/monorepo', const ['zonai']);

      final link = _resolve(
        fs,
        '/app',
        zonaiConfig: '/monorepo/.dart_tool/package_config.json',
        missingGeneratedSource: '/monorepo/apps/zonai/lib/gen/version.dart',
      );

      expect(link.canLink, isFalse);
      expect(
        link.skipReason,
        contains('/monorepo/apps/zonai/lib/gen/version.dart'),
        reason: 'the skip must name the file, not just say "not built"',
      );
      expect(
        link.skipReason,
        contains('worker processes'),
        reason: 'and must say what happens instead, like every other skip',
      );
    });

    test('does not write a merged config when the sources are not built', () {
      // Writing *is* the decision here (see resolveProjectLink's doc). A config
      // left behind for a graph that cannot compile is a trap for the next run,
      // which would find it and believe the link was resolved.
      final fs = MemoryFileSystem();
      _writePackageConfig(fs, '/app', const ['zonai_schema']);
      _writePackageConfig(fs, '/monorepo', const ['zonai']);

      _resolve(
        fs,
        '/app',
        zonaiConfig: '/monorepo/.dart_tool/package_config.json',
        missingGeneratedSource: '/monorepo/apps/zonai/lib/gen/version.dart',
      );

      expect(
        fs.file('/app/.dart_tool/zonai/package_config.json').existsSync(),
        isFalse,
      );
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
  String? missingGeneratedSource,
}) {
  return _run(
    fs,
    projectRoot,
    // Injected in every case, including the ones not about it: the real
    // implementation reads `dart:io`, so leaving it at its default would make
    // each of these tests depend on whether the checkout running them happens
    // to have been built.
    () => resolveProjectLink(
      findZonaiPackageConfig: () => zonaiConfig,
      findMissingGeneratedSource: () => missingGeneratedSource,
    ),
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
