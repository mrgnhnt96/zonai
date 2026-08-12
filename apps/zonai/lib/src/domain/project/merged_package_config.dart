// dart format width=100
/// Builds a package config that resolves the project's packages *and* zonai's
/// own, so the generated project entry can be compiled from a project that has
/// no `zonai` dependency.
///
/// The problem this exists for: `.dart_tool/zonai/project_main.dart` imports
/// `package:zonai/src/bootstrap.dart`, which only resolves inside a package
/// graph containing zonai. zonai ships as a standalone binary and is never an
/// application dependency, so [projectResolvesZonai] is false in every real
/// project and the in-process ops/rules path -- the whole point of a linked
/// binary -- has never applied to a real deployment.
///
/// `dart compile exe --packages=<file>` takes any config, so the way out is to
/// synthesise one from both graphs and compile against that.
///
/// THE MERGE IS NOT SYMMETRIC, and the asymmetry is not a preference. With the
/// app winning on collisions the compile fails at `resqlite_delegate.dart:302`
/// with `Method not found: 'SQLiteDelegate'`: published `zonai_schema 0.1.1`
/// deliberately keeps `SQLiteDelegate` out of its public barrel (issue #24), so
/// zonai's own sources cannot compile against the copy an app resolved. That is
/// structural, not version skew, and no amount of aligning versions fixes it.
/// With zonai winning it compiles and runs. Hence [mergePackageConfigs] letting
/// zonai's entry replace the project's, and reporting which ones it replaced so
/// a caller can say so out loud.
library;

import 'dart:convert';

import 'package:zonai/src/deps/fs.dart';

/// The merged config, plus the packages zonai's graph overrode.
class MergedPackageConfig {
  const MergedPackageConfig({required this.config, required this.overridden});

  /// The config document, ready to be JSON-encoded and passed to `--packages`.
  final Map<String, Object?> config;

  /// Packages the project resolved that zonai's graph replaced, sorted.
  ///
  /// Every entry here is a package the project's own code will now be compiled
  /// against a *different* version of than pub chose for it. That is the price
  /// of the direction the merge has to run in, so it is returned rather than
  /// swallowed -- a caller that never mentions it leaves a real behaviour
  /// change with nothing pointing at it.
  final List<String> overridden;
}

/// Merges [zonaiConfig] over [projectConfig], resolving every `rootUri` to an
/// absolute URI first.
///
/// Absolutising is not cosmetic. A `rootUri` is relative to the directory
/// holding *its own* config file, and the merged config is written somewhere
/// that is neither -- so carrying the relative strings across would silently
/// repoint packages at directories that do not exist, or worse, at ones that
/// do.
///
/// [projectConfigPath] and [zonaiConfigPath] are the paths of the two
/// `package_config.json` files themselves, not their directories.
MergedPackageConfig mergePackageConfigs({
  required Map<String, Object?> projectConfig,
  required String projectConfigPath,
  required Map<String, Object?> zonaiConfig,
  required String zonaiConfigPath,
}) {
  final merged = _absolutePackages(projectConfig, configPath: projectConfigPath);
  final zonaiPackages = _absolutePackages(zonaiConfig, configPath: zonaiConfigPath);

  final overridden = <String>[];
  for (final entry in zonaiPackages.entries) {
    final existing = merged[entry.key];
    // Only a package resolved to a *different* root is an override worth
    // reporting. A workspace project and the CLI beside it agree on most
    // packages already, and listing those would bury the handful that matter.
    if (existing != null && existing['rootUri'] != entry.value['rootUri']) {
      overridden.add(entry.key);
    }
    merged[entry.key] = entry.value;
  }

  final names = merged.keys.toList()..sort();

  return MergedPackageConfig(
    config: {
      'configVersion': 2,
      // No `generated` timestamp on purpose: this file is written on every
      // build, and a moving timestamp makes it impossible to tell "the package
      // graph changed" from "the clock moved" when one is staring at a diff.
      'generator': 'zonai',
      'packages': [for (final name in names) merged[name]],
    },
    overridden: overridden..sort(),
  );
}

/// The config's packages by name, with `rootUri` made absolute.
Map<String, Map<String, Object?>> _absolutePackages(
  Map<String, Object?> config, {
  required String configPath,
}) {
  // Resolve against the config FILE's URI: `Uri.resolve` treats the last
  // segment as a file and resolves relative to its directory, which is exactly
  // how the package_config spec defines rootUri.
  final base = fs.path.toUri(fs.path.absolute(configPath));

  final packages = <String, Map<String, Object?>>{};
  for (final raw in config['packages'] as List<Object?>? ?? const []) {
    if (raw is! Map) continue;
    final entry = <String, Object?>{for (final e in raw.entries) '${e.key}': e.value};

    final name = entry['name'];
    final rootUri = entry['rootUri'];
    if (name is! String || rootUri is! String) continue;

    entry['rootUri'] = '${base.resolve(rootUri)}';
    packages[name] = entry;
  }

  return packages;
}

/// Reads both configs, merges them, and writes the result to [outputPath].
///
/// Returns `null` when either config is missing or unreadable -- the same
/// judgement [projectResolvesZonai] makes about a half-written config: a build
/// that cannot see a package graph is not a build that should guess at one.
MergedPackageConfig? writeMergedPackageConfig({
  required String projectConfigPath,
  required String zonaiConfigPath,
  required String outputPath,
}) {
  final project = _readConfig(projectConfigPath);
  final zonai = _readConfig(zonaiConfigPath);
  if (project == null || zonai == null) return null;

  final merged = mergePackageConfigs(
    projectConfig: project,
    projectConfigPath: projectConfigPath,
    zonaiConfig: zonai,
    zonaiConfigPath: zonaiConfigPath,
  );

  fs.file(outputPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(merged.config)}\n');

  return merged;
}

Map<String, Object?>? _readConfig(String path) {
  final file = fs.file(path);
  if (!file.existsSync()) return null;

  try {
    return json.decode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (_) {
    return null;
  }
}
