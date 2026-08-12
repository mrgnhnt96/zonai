import 'dart:convert';

import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/project/merged_package_config.dart';

/// The merged config is what a linked binary gets compiled against, so a
/// package pointed at the wrong directory here is a compile failure at best and
/// a binary linked against the wrong source at worst. The cases below are the
/// ways that can happen: relative roots carried across unchanged, a collision
/// resolved the wrong way, or an entry quietly dropped.
void main() {
  group('mergePackageConfigs', () {
    test('resolves relative roots against each config\'s own directory', () {
      // The reason absolutising exists. Both configs say `../pkg`, but they sit
      // in different `.dart_tool` directories, so the same string names two
      // different places. Carried across verbatim, one of them would be wrong.
      final merged = _merge(
        projectPackages: [_pkg('app', '../app')],
        projectConfigPath: '/work/project/.dart_tool/package_config.json',
        zonaiPackages: [_pkg('zonai', '../apps/zonai')],
        zonaiConfigPath: '/work/zonai_repo/.dart_tool/package_config.json',
      );

      expect(_rootOf(merged, 'app'), 'file:///work/project/app');
      expect(_rootOf(merged, 'zonai'), 'file:///work/zonai_repo/apps/zonai');
    });

    test('leaves an already-absolute root alone', () {
      final merged = _merge(
        projectPackages: [_pkg('meta', 'file:///pub-cache/meta-1.0.0')],
        zonaiPackages: const [],
      );

      expect(_rootOf(merged, 'meta'), 'file:///pub-cache/meta-1.0.0');
    });

    test('zonai wins a collision', () {
      // Not a preference: with the app winning, zonai's own sources fail to
      // compile against a published zonai_schema that keeps SQLiteDelegate out
      // of its barrel (issue #24). Reversing this assertion reverses that.
      final merged = _merge(
        projectPackages: [
          _pkg('zonai_schema', 'file:///pub-cache/zonai_schema-0.1.1'),
        ],
        zonaiPackages: [
          _pkg('zonai_schema', 'file:///monorepo/libs/zonai_schema'),
        ],
      );

      expect(
        _rootOf(merged, 'zonai_schema'),
        'file:///monorepo/libs/zonai_schema',
      );
    });

    test('reports the packages it overrode', () {
      final merged = _merge(
        projectPackages: [
          _pkg('zonai_schema', 'file:///pub-cache/zonai_schema-0.1.1'),
          _pkg('zonai_client', 'file:///pub-cache/zonai_client-0.1.1'),
          _pkg('app_only', 'file:///project/app_only'),
        ],
        zonaiPackages: [
          _pkg('zonai_schema', 'file:///monorepo/libs/zonai_schema'),
          _pkg('zonai_client', 'file:///monorepo/libs/zonai_client'),
          _pkg('zonai', 'file:///monorepo/apps/zonai'),
        ],
      );

      expect(merged.overridden, ['zonai_client', 'zonai_schema']);
    });

    test('does not report a package both graphs already agree on', () {
      // A workspace project and the CLI beside it share most of their graph.
      // Reporting those would bury the handful that genuinely changed.
      final merged = _merge(
        projectPackages: [_pkg('meta', 'file:///pub-cache/meta-1.0.0')],
        zonaiPackages: [_pkg('meta', 'file:///pub-cache/meta-1.0.0')],
      );

      expect(merged.overridden, isEmpty);
    });

    test('keeps every package from both graphs', () {
      final merged = _merge(
        projectPackages: [
          _pkg('app_only', 'file:///a'),
          _pkg('shared', 'file:///b'),
        ],
        zonaiPackages: [
          _pkg('zonai_only', 'file:///c'),
          _pkg('shared', 'file:///d'),
        ],
      );

      expect(_names(merged), ['app_only', 'shared', 'zonai_only']);
    });

    test('preserves the fields the SDK reads back', () {
      // packageUri and languageVersion are not decoration -- dropping either
      // changes how the package resolves or which language features compile.
      final merged = _merge(
        projectPackages: const [],
        zonaiPackages: [
          {
            'name': 'zonai',
            'rootUri': 'file:///monorepo/apps/zonai',
            'packageUri': 'lib/',
            'languageVersion': '3.12',
          },
        ],
      );

      final entry = _entryOf(merged, 'zonai');
      expect(entry['packageUri'], 'lib/');
      expect(entry['languageVersion'], '3.12');
    });

    test('emits configVersion 2 and sorted, stable output', () {
      // No `generated` timestamp: this is rewritten on every build, and a
      // moving clock would make every diff look like a graph change.
      final merged = _merge(
        projectPackages: [
          _pkg('zeta', 'file:///z'),
          _pkg('alpha', 'file:///a'),
        ],
        zonaiPackages: const [],
      );

      expect(merged.config['configVersion'], 2);
      expect(merged.config.containsKey('generated'), isFalse);
      expect(_names(merged), ['alpha', 'zeta']);
    });

    test('skips malformed entries rather than emitting a broken config', () {
      final merged = _merge(
        projectPackages: const [
          {'name': 'good', 'rootUri': 'file:///good'},
          {'name': 'no_root'},
          {'rootUri': 'file:///no-name'},
        ],
        zonaiPackages: const [],
      );

      expect(_names(merged), ['good']);
    });
  });

  group('writeMergedPackageConfig', () {
    test('writes a config the merge round-trips through JSON', () {
      final fileSystem = MemoryFileSystem();
      _write(fileSystem, '/project/.dart_tool/package_config.json', [
        _pkg('zonai_schema', 'file:///pub-cache/zonai_schema-0.1.1'),
      ]);
      _write(fileSystem, '/monorepo/.dart_tool/package_config.json', [
        _pkg('zonai', '../apps/zonai'),
        _pkg('zonai_schema', '../libs/zonai_schema'),
      ]);

      final result = _run(
        fileSystem,
        () => writeMergedPackageConfig(
          projectConfigPath: '/project/.dart_tool/package_config.json',
          zonaiConfigPath: '/monorepo/.dart_tool/package_config.json',
          outputPath: '/project/.dart_tool/zonai/package_config.json',
        ),
      );

      expect(result, isNotNull);
      expect(result!.overridden, ['zonai_schema']);

      final written =
          json.decode(
                fileSystem
                    .file('/project/.dart_tool/zonai/package_config.json')
                    .readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(written['configVersion'], 2);
      final packages = (written['packages'] as List)
          .cast<Map<String, Object?>>();
      expect(packages.map((p) => p['name']), ['zonai', 'zonai_schema']);
      expect(
        packages.firstWhere((p) => p['name'] == 'zonai_schema')['rootUri'],
        'file:///monorepo/libs/zonai_schema',
      );
    });

    test('returns null when the project config is missing', () {
      // A build that cannot see a package graph should fall back, not guess.
      final fileSystem = MemoryFileSystem();
      _write(fileSystem, '/monorepo/.dart_tool/package_config.json', [
        _pkg('zonai', '../a'),
      ]);

      expect(
        _run(
          fileSystem,
          () => writeMergedPackageConfig(
            projectConfigPath: '/project/.dart_tool/package_config.json',
            zonaiConfigPath: '/monorepo/.dart_tool/package_config.json',
            outputPath: '/out/package_config.json',
          ),
        ),
        isNull,
      );
    });

    test('returns null when zonai\'s config is missing', () {
      // The bare-released-binary case: no zonai sources on disk to merge.
      final fileSystem = MemoryFileSystem();
      _write(fileSystem, '/project/.dart_tool/package_config.json', [
        _pkg('app', 'file:///a'),
      ]);

      expect(
        _run(
          fileSystem,
          () => writeMergedPackageConfig(
            projectConfigPath: '/project/.dart_tool/package_config.json',
            zonaiConfigPath: '/monorepo/.dart_tool/package_config.json',
            outputPath: '/out/package_config.json',
          ),
        ),
        isNull,
      );
    });

    test('returns null on a half-written config rather than throwing', () {
      final fileSystem = MemoryFileSystem();
      fileSystem.file('/project/.dart_tool/package_config.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"packages": [');
      _write(fileSystem, '/monorepo/.dart_tool/package_config.json', [
        _pkg('zonai', '../a'),
      ]);

      expect(
        _run(
          fileSystem,
          () => writeMergedPackageConfig(
            projectConfigPath: '/project/.dart_tool/package_config.json',
            zonaiConfigPath: '/monorepo/.dart_tool/package_config.json',
            outputPath: '/out/package_config.json',
          ),
        ),
        isNull,
      );
    });
  });
}

Map<String, Object?> _pkg(String name, String rootUri) => {
  'name': name,
  'rootUri': rootUri,
  'packageUri': 'lib/',
};

MergedPackageConfig _merge({
  required List<Map<String, Object?>> projectPackages,
  required List<Map<String, Object?>> zonaiPackages,
  String projectConfigPath = '/project/.dart_tool/package_config.json',
  String zonaiConfigPath = '/monorepo/.dart_tool/package_config.json',
}) {
  return _run(
    MemoryFileSystem(),
    () => mergePackageConfigs(
      projectConfig: {'configVersion': 2, 'packages': projectPackages},
      projectConfigPath: projectConfigPath,
      zonaiConfig: {'configVersion': 2, 'packages': zonaiPackages},
      zonaiConfigPath: zonaiConfigPath,
    ),
  );
}

List<Map<String, Object?>> _packages(MergedPackageConfig merged) =>
    (merged.config['packages'] as List).cast<Map<String, Object?>>();

List<String> _names(MergedPackageConfig merged) => [
  for (final p in _packages(merged)) p['name'] as String,
];

Map<String, Object?> _entryOf(MergedPackageConfig merged, String name) =>
    _packages(merged).firstWhere((p) => p['name'] == name);

String _rootOf(MergedPackageConfig merged, String name) =>
    _entryOf(merged, name)['rootUri'] as String;

void _write(
  MemoryFileSystem fileSystem,
  String path,
  List<Map<String, Object?>> packages,
) {
  fileSystem.file(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      json.encode({'configVersion': 2, 'packages': packages}),
    );
}

T _run<T>(MemoryFileSystem fileSystem, T Function() body) =>
    runScoped(body, values: {fsProvider.overrideWith(() => fileSystem)});
