/// Generates `lib/src/gen/version.dart` from the repository's `VERSION` file.
///
/// The marketing site shows the version in three places that must never
/// disagree with what was actually released: the nav badge, the `curl` install
/// line, and every download URL. Rather than hand-editing a constant, they all
/// derive from the same `VERSION` file the release workflow writes and commits.
///
///   dart run tool/sync_version.dart           # write the generated file
///   dart run tool/sync_version.dart --check   # fail if it is out of date
///
/// The generated file is committed so a plain `jaspr build` works without a
/// pre-step; `--check` in CI is what stops it drifting.
library;

import 'dart:io';

void main(List<String> args) {
  final check = args.contains('--check');

  final root = _repoRoot();
  final versionFile = File('${root.path}/VERSION');
  if (!versionFile.existsSync()) {
    stderr.writeln('Could not find VERSION at ${versionFile.path}');
    exit(1);
  }

  final version = versionFile.readAsStringSync().trim();
  if (!RegExp(r'^\d+\.\d+\.\d+([-+].+)?$').hasMatch(version)) {
    stderr.writeln('VERSION does not look like a semver: "$version"');
    exit(1);
  }

  final target = File('${Directory.current.path}/lib/src/gen/version.dart');
  final contents = _render(version);

  if (check) {
    final actual = target.existsSync() ? target.readAsStringSync() : '';
    if (actual == contents) {
      stdout.writeln('version.dart is up to date (v$version)');
      return;
    }
    stderr
      ..writeln('lib/src/gen/version.dart is out of date.')
      ..writeln('VERSION is "$version". Run: dart run tool/sync_version.dart')
      ..writeln()
      ..writeln('The site would otherwise advertise a version that was never released,')
      ..writeln('and link to download URLs under a tag that may not exist.');
    exit(1);
  }

  target.parent.createSync(recursive: true);
  target.writeAsStringSync(contents);
  stdout.writeln('Wrote ${target.path} (v$version)');
}

/// Walks up from the current directory to the directory holding `VERSION`.
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/VERSION').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  stderr.writeln('Could not locate the repository root from ${Directory.current.path}');
  exit(1);
}

String _render(String version) => '''
// GENERATED FILE — DO NOT EDIT.
//
// Produced by `dart run tool/sync_version.dart` from the repository VERSION
// file. The release workflow regenerates this, so editing it by hand is only
// ever undone.

/// The released Zonai CLI version this build of the site describes.
const zonaiVersion = '$version';
''';
