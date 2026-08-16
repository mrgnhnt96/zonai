// Fails when `apps/zonai/lib/gen/server` no longer mirrors `apps/server`.
//
// Run from apps/zonai:
//   dart run tool/server_mirror_check.dart
//
// `zonai compile` embeds the revali server by COPYING apps/server to
// apps/zonai/lib/gen/server (`server.sync-to-cli` in scripts.yaml). The copy is
// gitignored, so it is not a build artifact git can keep honest: it is whatever
// the last sync left behind, on this machine, from whatever branch was checked
// out at the time.
//
// That goes wrong in two ways, and both have cost real time:
//
//  1. Edit a route, a handler or a sealed exception in apps/server, run the
//     tests, and they compile the OLD mirror. Extending a sealed AuthException
//     is the sharpest version -- the mirror's exception_catcher.dart still
//     switches exhaustively over the old set, so it fails to compile with an
//     error naming a type the developer just added and did nothing wrong with.
//  2. A git worktree gets the mirror INJECTED from the main checkout
//     (.showrunner/config.json, `inject`), which is usually on a different
//     branch. Every test in apps/server and apps/zonai then fails to load with
//     an error about a type from somebody else's feature.
//
// `dart analyze` cannot see either, structurally: analysis_options.yaml excludes
// `**/lib/gen/**`. Only `dart test` catches it, and it catches it as a wall of
// unrelated-looking load failures rather than as "your mirror is stale".
//
// This check turns that into one line naming the fix. It is a comparison, not a
// stamp: the mirror is a straight copy, so the two trees must be byte-identical
// and there is no sidecar to write, forget to write, or have drift on its own.
//
// WHAT IT DOES NOT SEE. `.revali/` is excluded. It is regenerated output whose
// determinism this check does not rely on, so a mirror whose `.revali` is stale
// while its sources match still passes here. That case is caught by `dart test`
// the old way. Excluding it is the price of a check that never flaps; a flapping
// gate gets disabled, and then it guards nothing.
import 'dart:io';

import 'package:path/path.dart' as p;

/// Source trees under `apps/server` that `server.sync-to-cli` copies verbatim.
///
/// `lib/` includes the tracked, generated `lib/gen/swagger_assets.dart` on
/// purpose: a swagger regeneration that was never synced is the same class of
/// staleness as an edited route.
const _mirroredPaths = ['routes', 'lib'];

Future<void> main(List<String> args) async {
  final zonaiRoot = Directory.current.absolute.path;
  final repoRoot = p.normalize(p.join(zonaiRoot, '..', '..'));
  final source = p.join(repoRoot, 'apps', 'server');
  final mirror = p.join(zonaiRoot, 'lib', 'gen', 'server');

  if (!Directory(source).existsSync()) {
    stdout.writeln(
      'server-mirror: no apps/server at $source -- run this from apps/zonai.',
    );
    exitCode = 2;
    return;
  }

  if (!Directory(mirror).existsSync()) {
    _fail(
      'lib/gen/server is missing entirely, so `zonai compile` has nothing to '
      'embed.',
    );
    return;
  }

  final differences = <String>[];
  for (final relative in _mirroredPaths) {
    differences.addAll(
      _compare(
        sourceDir: p.join(source, relative),
        mirrorDir: p.join(mirror, relative),
        label: relative,
      ),
    );
  }

  if (differences.isEmpty) {
    stdout.writeln(
      'server-mirror: lib/gen/server matches apps/server '
      '(${_mirroredPaths.join(', ')}; .revali not compared).',
    );
    return;
  }

  _fail(
    'lib/gen/server no longer matches apps/server:\n'
    '${differences.take(10).map((d) => '    $d').join('\n')}'
    '${differences.length > 10 ? '\n    ... and ${differences.length - 10} more' : ''}',
  );
}

void _fail(String what) {
  stdout
    ..writeln('server-mirror: STALE')
    ..writeln('  $what')
    ..writeln('')
    ..writeln(
      '  apps/zonai/lib/gen/server is a gitignored COPY of apps/server that '
      '`zonai compile` embeds.',
    )
    ..writeln(
      '  Until it is resynced, apps/server and apps/zonai tests compile the '
      'old copy and fail',
    )
    ..writeln(
      '  with errors that name types you did nothing wrong with. '
      '`dart analyze` cannot see this:',
    )
    ..writeln('  analysis_options.yaml excludes **/lib/gen/**.')
    ..writeln('')
    ..writeln('  Fix, from the repo root:')
    ..writeln('    sip run server copy-to-cli')
    ..writeln('')
    ..writeln(
      '  In a git worktree `sip` may resolve to the MAIN checkout -- run the '
      'steps directly there:',
    )
    ..writeln(
      '    cd apps/server && dart run revali dev --generate-only --flavor dev '
      '--release --recompile',
    )
    ..writeln('    then the `server.sync-to-cli` steps in scripts.yaml');
  exitCode = 1;
}

/// Every path under [sourceDir] that is missing from, or differs in, [mirrorDir]
/// — plus anything in the mirror the source no longer has.
List<String> _compare({
  required String sourceDir,
  required String mirrorDir,
  required String label,
}) {
  final sourceFiles = _filesUnder(sourceDir);
  final mirrorFiles = _filesUnder(mirrorDir);
  final differences = <String>[];

  for (final entry in sourceFiles.entries) {
    final mirrored = mirrorFiles[entry.key];
    if (mirrored == null) {
      differences.add('$label/${entry.key} is missing from the mirror');
    } else if (mirrored != entry.value) {
      differences.add('$label/${entry.key} differs');
    }
  }

  for (final key in mirrorFiles.keys) {
    if (!sourceFiles.containsKey(key)) {
      differences.add(
        '$label/$key is in the mirror but no longer in the source',
      );
    }
  }

  differences.sort();
  return differences;
}

/// Relative path -> file length and modification-independent content hash.
///
/// Content is compared by bytes rather than by mtime: a copy has whatever
/// timestamps the copy gave it, and mtime would report every fresh sync as a
/// difference.
Map<String, String> _filesUnder(String root) {
  final directory = Directory(root);
  if (!directory.existsSync()) return const {};

  final files = <String, String>{};
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = p.url.joinAll(
      p.split(p.relative(entity.path, from: root)),
    );
    // Generated-by-tooling directories the sync does not carry, or that are
    // rebuilt per-tree. `.revali` is excluded for the reason at the top of this
    // file; the rest are never copied at all.
    if (relative.startsWith('.dart_tool/') ||
        relative.startsWith('.revali/') ||
        relative.startsWith('build/')) {
      continue;
    }
    files[relative] = _hash(entity);
  }
  return files;
}

String _hash(File file) {
  final bytes = file.readAsBytesSync();
  // FNV-1a over the bytes: enough to catch an edit, and avoids pulling a crypto
  // dependency into a check that runs on every `test static`.
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return '${bytes.length}:${hash.toRadixString(16)}';
}
