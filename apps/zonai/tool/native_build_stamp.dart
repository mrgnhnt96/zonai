// Records and verifies what the cached native libraries were built from.
//
// Run from apps/zonai:
//   dart run tool/native_build_stamp.dart write --library resqlite [--arch x64]
//   dart run tool/native_build_stamp.dart check --library argon2
//
// `write` runs after a real source build (native-libs.yml, and the from-source
// branch of `resqlite.gen`/`argon2.gen`). `check` runs before trusting a
// downloaded artifact, and exits 1 -- with the reason on stdout, so it lands in
// the CI log next to the decision it explains -- when the cache no longer
// matches this checkout. See tool/src/native_build_stamp.dart for why.
//
// This file is argument parsing and output only: what each library actually
// depends on lives in tool/src/native_build_stamp.dart, where a test can point
// it at the real repo and catch a path or package name that has stopped
// resolving. A fingerprint over inputs that silently went missing is the exact
// failure the whole mechanism exists to prevent, so it must not be able to hide
// in a script no test can reach.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zonai/src/domain/arch.dart';

import 'src/native_build_stamp.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || (args.first != 'write' && args.first != 'check')) {
    _usage('Expected a `write` or `check` command.');
  }
  final command = args.first;
  final library = NativeLibrary.byName(_optionValue(args, '--library'));
  if (library == null) {
    _usage(
      '--library must be one of '
      '${NativeLibrary.values.map((l) => l.name).join(', ')}.',
    );
  }

  final zonaiRoot = Directory.current.absolute.path;
  final repoRoot = p.normalize(p.join(zonaiRoot, '..', '..'));
  // `--arch` mirrors the flag `libs/resqlite/tool/build_native.dart` takes, and
  // its values are `package:code_assets`' `Architecture` names -- which [Arch]
  // already spells identically, so the two stay in step without a mapping.
  final targetArch = _optionValue(args, '--arch') ?? Arch.current().name;

  final libraryPath = library.libraryPath(zonaiRoot: zonaiRoot);
  final inputs = await library.inputs(
    repoRoot: repoRoot,
    targetArch: targetArch,
  );
  final fingerprint = fingerprintOf(inputs, root: repoRoot);

  if (command == 'write') {
    writeFingerprint(libraryPath, fingerprint);
    stdout.writeln(
      'Stamped ${p.basename(libraryPath)} with build inputs $fingerprint',
    );
    return;
  }

  final reason = checkFingerprint(libraryPath, fingerprint);
  if (reason != null) {
    stdout.writeln(
      'Cannot reuse the prebuilt ${library.name} library: $reason.',
    );
    // Falling back to a source build is correct but silent, and the cache
    // stays stale until someone dispatches native-libs.yml again -- so every
    // later run pays the same rebuild for the same reason. Surface it where a
    // human will actually see it. Only under Actions: locally this branch is
    // the normal path, not news.
    if (Platform.environment['GITHUB_ACTIONS'] == 'true') {
      stdout.writeln(
        '::warning::The cached ${library.name} native library is stale '
        '($reason). Building from source instead. Dispatch the '
        '"Native Libraries" workflow to refresh the cache.',
      );
    }
    exit(1);
  }
  stdout.writeln(
    '${p.basename(libraryPath)} matches this checkout ($fingerprint).',
  );
}

String? _optionValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Never _usage(String message) {
  stderr.writeln(
    '$message\n\n'
    'Usage: dart run tool/native_build_stamp.dart <write|check> '
    '--library <${NativeLibrary.values.map((l) => l.name).join('|')}> '
    '[--arch <architecture>]',
  );
  exit(64);
}
