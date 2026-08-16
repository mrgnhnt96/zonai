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
// stamp: there is no sidecar to write, forget to write, or have drift on its own.
//
// THE MIRROR IS NOT A STRAIGHT COPY. `server.sync-to-cli` rewrites imports
// inside the copy, because the mirror lives inside `apps/zonai`, which does not
// depend on `zonai_server` -- a verbatim `package:zonai_server/...` import would
// not resolve there at all. So this replicates the two rewrites (see
// [_syncedSource]) and compares the transformed source, not the raw bytes.
//
// The first version of this check asserted the opposite -- "the mirror is a
// straight copy, so the two trees must be byte-identical" -- and was wrong in
// BOTH directions, each observed on this branch:
//
//   * false STALE: a mirror resynced correctly with `sip run server copy-to-cli`
//     reported 11 files differing. They were exactly the files containing
//     `package:zonai_server`. A gate that fires on correct work gets ignored,
//     and then it guards nothing.
//   * false CLEAN: a mirror produced by running the recipe's steps by hand and
//     skipping the perl rewrite reported "matches". Those imports resolve
//     nowhere once `zonai compile` embeds them, and the byte comparison called
//     it good precisely because the un-rewritten copy IS byte-identical.
//
// That second one is why the rewrite is replicated rather than ignored: the
// unsynced state and the correctly-synced state differ only in these imports,
// so a check blind to them cannot tell the two apart.
//
// WHAT IT DOES NOT SEE. `.revali/` is excluded. It is regenerated output whose
// determinism this check does not rely on, so a mirror whose `.revali` is stale
// while its sources match still passes here. That case is caught by `dart test`
// the old way. Excluding it is the price of a check that never flaps; a flapping
// gate gets disabled, and then it guards nothing.
import 'dart:convert';
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
        // `find lib -exec perl ... 's|package:zonai_server/src|..|'` runs only
        // under lib/; the second rewrite runs over everything.
        underLib: relative == 'lib',
      ),
    );
  }

  if (_unrewrittenPackageImports.isNotEmpty) {
    stdout
      ..writeln('server-mirror: THIS CHECK IS OUT OF DATE')
      ..writeln(
        '  ${_unrewrittenPackageImports.length} source file(s) still name '
        '`package:zonai_server` after this check',
      )
      ..writeln(
        '  replayed `server.sync-to-cli`\'s rewrites, so the rewrite list in '
        '_syncedSource no longer',
      )
      ..writeln('  matches the recipe in scripts.yaml. For example:')
      ..writeln('    ${_unrewrittenPackageImports.first}')
      ..writeln('')
      ..writeln(
        '  Until they agree, this check compares the source against a '
        'transform the sync does not',
      )
      ..writeln(
        '  perform, and every verdict below it is meaningless. Fix '
        '_syncedSource first.',
      );
    exitCode = 1;
    return;
  }

  if (differences.isEmpty) {
    stdout.writeln(
      'server-mirror: lib/gen/server matches apps/server '
      '(${_mirroredPaths.join(', ')}; import rewrites replayed; '
      '.revali not compared).',
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
    ..writeln('    then EVERY `server.sync-to-cli` step in scripts.yaml.')
    ..writeln('')
    ..writeln(
      '  Run them all. The two `perl -pi -e` import rewrites are the easiest '
      'to drop when running',
    )
    ..writeln(
      '  the recipe by hand, and a copy that skips them is the one state this '
      'check exists to name.',
    );
  exitCode = 1;
}

/// Every path under [sourceDir] that is missing from, or differs in, [mirrorDir]
/// — plus anything in the mirror the source no longer has.
List<String> _compare({
  required String sourceDir,
  required String mirrorDir,
  required String label,
  required bool underLib,
}) {
  final sourceFiles = _filesUnder(sourceDir, underLib: underLib, sync: true);
  final mirrorFiles = _filesUnder(mirrorDir, underLib: underLib, sync: false);
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
///
/// With [sync] set, Dart files are transformed by [_syncedSource] first, so the
/// source side is hashed as the sync would have written it.
Map<String, String> _filesUnder(
  String root, {
  required bool underLib,
  required bool sync,
}) {
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
    final transform = sync && p.extension(relative) == '.dart';
    files[relative] = _hash(entity, syncImports: transform, underLib: underLib);
  }
  return files;
}

/// `server.sync-to-cli`'s two in-place rewrites, in its order.
///
/// Kept deliberately literal so a reader can line them up against the recipe in
/// `scripts.yaml` (`server.sync-to-cli`). If that recipe gains a third rewrite
/// and this does not, [_unrewrittenPackageImports] is what says so — rather than
/// this reporting a pile of files as "differs" and leaving someone to work out
/// why a clean sync looks dirty.
String _syncedSource(String contents, {required bool underLib}) {
  var out = contents;
  if (underLib) {
    out = out.replaceAll('package:zonai_server/src', '..');
  }
  return out.replaceAll('package:zonai_server', '../../lib');
}

/// Source files still naming `package:zonai_server` after [_syncedSource] ran.
///
/// There should never be any: the mirror lives in a package that does not
/// depend on `zonai_server`, so an import the rewrites missed is one that
/// resolves nowhere once `zonai compile` embeds the copy. Finding one means the
/// rewrite list here has drifted from the recipe.
final _unrewrittenPackageImports = <String>[];

String _hash(File file, {required bool syncImports, required bool underLib}) {
  var bytes = file.readAsBytesSync();
  if (syncImports) {
    final synced = _syncedSource(
      utf8.decode(bytes, allowMalformed: true),
      underLib: underLib,
    );
    if (synced.contains('package:zonai_server')) {
      _unrewrittenPackageImports.add(file.path);
    }
    bytes = utf8.encode(synced);
  }
  // FNV-1a over the bytes: enough to catch an edit, and avoids pulling a crypto
  // dependency into a check that runs on every `test static`.
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return '${bytes.length}:${hash.toRadixString(16)}';
}
