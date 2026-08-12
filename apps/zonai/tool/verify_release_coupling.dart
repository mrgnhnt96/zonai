// Asks one question, against pub.dev: can a real consumer actually get a
// `zonai_schema` at or above the floor this CLI declares?
//
// Two things have to be true, and forgetting either has already happened:
//
//   1. The floor is published. `zonai init` scaffolds
//      `zonai_schema: ^<kMinSchemaVersion>`, so a CLI released ahead of the
//      schema it names hands new projects a pubspec pub cannot resolve. The
//      floor used to be `kVersion` itself -- the scaffold asked for ^0.6.2
//      while pub.dev's newest zonai_schema was 0.1.1.
//
//   2. Our other published packages allow it. `zonai_client` 0.1.1 declares
//      `zonai_schema: ^0.1.0`, which excludes 0.2.0 -- so publishing the
//      schema alone leaves every consumer who also uses the client unable to
//      upgrade. Widening the constraint in this repo does nothing for them
//      until the client is published too.
//
// Neither is visible from a test suite: every checkout here resolves
// zonai_schema by path, and the constraints that matter are the ones already
// on pub.dev, not the ones in the working tree.
//
// This does NOT check that the floor is high *enough*. That is a human
// judgement (see kMinSchemaVersion's own docs) and a floor left too low fails
// at the consumer, not here.
//
// Run: dart run tool/verify_release_coupling.dart   (from apps/zonai)
import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

const _schema = 'zonai_schema';

Future<void> main() async {
  final repoRoot = _repoRoot();
  final floor = _readFloor(repoRoot);
  stdout.writeln('Declared $_schema floor: $floor\n');

  final problems = <String>[];
  final pending = <String>[];

  // (1) Is the floor itself published?
  final schemaInfo = await _pubDev(_schema);
  if (!schemaInfo.versions.contains(floor.toString())) {
    problems.add(
      '$_schema $floor is NOT published (pub.dev has: '
      '${schemaInfo.versions.join(', ')}).\n'
      '    `zonai init` writes "$_schema: ^$floor", so a new project would '
      'fail to resolve.\n'
      '    Publish $_schema $floor before releasing the CLI.',
    );
  } else {
    stdout.writeln('OK   $_schema $floor is published.');
  }

  // (2) Do our other published packages admit it?
  //
  // Discovered from the repo rather than hardcoded, so a third publishable
  // package that depends on the schema is covered the day it lands instead of
  // the day someone remembers to add it here.
  for (final pkg in _publishablePackages(repoRoot)) {
    if (pkg.name == _schema) {
      if (pkg.version != floor.toString()) {
        pending.add(
          '$_schema is ${pkg.version} in this repo but the floor is $floor',
        );
      }
      continue;
    }

    final declared = pkg.schemaConstraint;
    if (declared == null) continue;

    final info = await _pubDev(pkg.name);
    final publishedConstraint = info.latestSchemaConstraint;
    if (publishedConstraint == null) {
      stdout.writeln(
        'SKIP ${pkg.name} ${info.latest} declares no $_schema dependency.',
      );
      continue;
    }

    if (VersionConstraint.parse(publishedConstraint).allows(floor)) {
      stdout.writeln(
        'OK   ${pkg.name} ${info.latest} allows $_schema $floor '
        '("$publishedConstraint").',
      );
      continue;
    }

    final fixedLocally = VersionConstraint.parse(declared).allows(floor);
    problems.add(
      'The PUBLISHED ${pkg.name} ${info.latest} declares '
      '"$_schema: $publishedConstraint", which excludes $floor.\n'
      '    Consumers using ${pkg.name} cannot upgrade $_schema to the floor '
      'until a new ${pkg.name} is published.\n'
      '    ${fixedLocally ? 'This repo already widens it to "$declared" -- that '
                'change only reaches consumers once ${pkg.name} is published.' : 'This repo still declares "$declared", which also excludes '
                '$floor. Widen it first.'}',
    );
  }

  // Not a failure on its own -- an unpublished bump is the normal state
  // between preparing a release and cutting it. It is here so the reason the
  // checks above fail is visible in the same output.
  for (final pkg in _publishablePackages(repoRoot)) {
    final info = await _pubDev(pkg.name);
    if (info.latest != pkg.version) {
      pending.add(
        '${pkg.name}: repo has ${pkg.version}, pub.dev has ${info.latest}',
      );
    }
  }

  if (pending.isNotEmpty) {
    stdout.writeln('\nUnpublished in this repo:');
    for (final p in pending.toSet()) {
      stdout.writeln('  - $p');
    }
  }

  if (problems.isEmpty) {
    stdout.writeln('\nRelease coupling OK.');
    return;
  }

  stderr.writeln(
    '\nFAIL: the declared floor is not reachable by a consumer.\n',
  );
  for (final p in problems) {
    stderr.writeln('  - $p\n');
  }
  stderr.writeln('See docs/releasing.md for the order these go out in.');
  exitCode = 1;
}

class _Package {
  _Package({
    required this.name,
    required this.version,
    required this.schemaConstraint,
  });

  final String name;
  final String version;

  /// This package's declared `zonai_schema` constraint in the working tree, or
  /// `null` when it doesn't depend on it.
  final String? schemaConstraint;
}

/// Every package under `libs/` that is **ours** and that pub would accept --
/// not marked `publish_to: none`, and pointing at this repo.
///
/// The repository check is what keeps vendored third-party sources out.
/// `libs/resqlite` is publishable-looking but belongs to someone else, and
/// there is an unrelated `resqlite` on pub.dev -- without this filter it gets
/// compared against a stranger's version numbers and reported as ours, which
/// is the kind of false line that teaches people to skim past real ones.
List<_Package> _publishablePackages(String repoRoot) {
  final out = <_Package>[];
  final libs = Directory('$repoRoot/libs');
  if (!libs.existsSync()) return out;

  for (final dir in libs.listSync().whereType<Directory>()) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;

    final text = pubspec.readAsStringSync();
    if (RegExp(r'^publish_to:\s*none', multiLine: true).hasMatch(text)) {
      continue;
    }

    final repository = _scalar(text, 'repository') ?? '';
    if (!repository.contains('mrgnhnt96/zonai')) continue;

    final name = _scalar(text, 'name');
    final version = _scalar(text, 'version');
    if (name == null || version == null) continue;

    out.add(
      _Package(
        name: name,
        version: version,
        schemaConstraint: _dependencyConstraint(text, _schema),
      ),
    );
  }
  return out;
}

String? _scalar(String pubspec, String key) => RegExp(
  '^$key:\\s*(.+)\$',
  multiLine: true,
).firstMatch(pubspec)?.group(1)?.trim();

/// The constraint declared for [dep], as written. Handles both the inline
/// `dep: ^1.0.0` form and a quoted range.
String? _dependencyConstraint(String pubspec, String dep) {
  final match = RegExp(
    '^\\s\\s$dep:\\s*(.+)\$',
    multiLine: true,
  ).firstMatch(pubspec);
  final raw = match?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  return raw.replaceAll('"', '').replaceAll("'", '');
}

Version _readFloor(String repoRoot) {
  final file = File(
    '$repoRoot/apps/zonai/lib/src/domain/schema_version/min_schema_version.dart',
  );
  if (!file.existsSync()) {
    stderr.writeln(
      'FAIL: ${file.path} is missing -- did kMinSchemaVersion move?',
    );
    exit(1);
  }

  final raw = RegExp(
    r"const kMinSchemaVersion = '([^']+)';",
  ).firstMatch(file.readAsStringSync())?.group(1);

  if (raw == null) {
    stderr.writeln(
      'FAIL: could not read kMinSchemaVersion out of ${file.path}.\n'
      "      Expected a line like: const kMinSchemaVersion = '0.2.0';",
    );
    exit(1);
  }

  return Version.parse(raw);
}

class _PubInfo {
  _PubInfo({
    required this.versions,
    required this.latest,
    required this.latestSchemaConstraint,
  });

  final List<String> versions;
  final String latest;

  /// The `zonai_schema` constraint declared by the *published* latest -- the
  /// one consumers actually resolve against.
  final String? latestSchemaConstraint;
}

final _cache = <String, _PubInfo>{};

Future<_PubInfo> _pubDev(String package) async {
  if (_cache[package] case final cached?) return cached;

  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('https://pub.dev/api/packages/$package'),
    );
    final response = await request.close();
    if (response.statusCode != 200) {
      stderr.writeln(
        'FAIL: pub.dev returned ${response.statusCode} for $package.',
      );
      exit(1);
    }

    final body =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;

    final versions = [
      for (final v in body['versions'] as List<dynamic>)
        (v as Map<String, dynamic>)['version'] as String,
    ];
    final latest = body['latest'] as Map<String, dynamic>;
    final pubspec = latest['pubspec'] as Map<String, dynamic>;
    final deps = pubspec['dependencies'] as Map<String, dynamic>?;

    return _cache[package] = _PubInfo(
      versions: versions,
      latest: latest['version'] as String,
      latestSchemaConstraint: deps?[_schema]?.toString(),
    );
  } finally {
    client.close();
  }
}

String _repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (Directory('${dir.path}/.git').existsSync() ||
        File('${dir.path}/VERSION').existsSync()) {
      return dir.path;
    }
    if (dir.parent.path == dir.path) {
      stderr.writeln(
        'FAIL: could not find the repo root from ${Directory.current.path}.',
      );
      exit(1);
    }
    dir = dir.parent;
  }
}
