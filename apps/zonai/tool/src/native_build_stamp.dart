// Freshness stamps for the native libraries CI caches between runs.
//
// `compile.yml` downloads the newest successful `native-libs.yml` artifact
// rather than rebuilding libresqlite/libargon2sodium from source, which saves
// minutes per platform per run. What made that unsafe was the check gating it:
// it only asked whether the library file was *there*. Move the resqlite
// submodule pin, or edit the argon2 builder, and the cached bytes no longer
// correspond to the sources in this checkout -- but the check still passes and
// the binary embeds them anyway. Nothing fails; a stale library just ships.
//
// So each library gets a sidecar recording a fingerprint of the inputs it was
// built from. [checkFingerprint] recomputes that fingerprint from the working
// tree and refuses the cache unless it matches, turning "the file exists" into
// "the file was built from these sources".
//
// Deliberately NOT the same thing as `lib/src/domain/native_library_stamp.dart`
// (`.stamp`), which travels with a *released* binary and answers "which release
// and target did these bytes come from". This one never leaves CI and answers
// "which sources were these bytes built from" -- different question, different
// suffix, so a reader is never left guessing which stamp they're looking at.
//
// What this does NOT catch: toolchain drift that leaves every input file
// identical. A runner image upgrading its clang/MSVC produces different bytes
// from the same sources, and the fingerprint cannot see it. [BuildInputs.facts]
// carries the Dart SDK version for that reason, but the C compiler has no
// equally cheap identifier, so that gap stays open and stated rather than
// papered over.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:zonai/src/native/argon2_ffi.dart' as argon2_ffi;

/// Everything a native library's bytes depend on.
///
/// [roots] must name directories that hold *only* source -- they are walked
/// recursively with nothing filtered out, so a build-output directory listed
/// here would make the fingerprint change on every build and the cache never
/// hit. Choosing pure-source roots is the reason there is no exclude list to
/// get wrong.
class BuildInputs {
  const BuildInputs({
    this.roots = const [],
    this.files = const [],
    this.facts = const {},
  });

  /// Directories walked recursively; every file beneath them is an input.
  final List<String> roots;

  /// Individual input files.
  final List<String> files;

  /// Inputs that aren't files: the target triple, the Dart SDK version, a
  /// dependency version resolved from a lockfile that isn't committed.
  final Map<String, String> facts;
}

/// The sidecar path recording what [libraryPath] was built from.
String buildStampPathFor(String libraryPath) => '$libraryPath.build-inputs';

/// The native libraries `zonai compile` embeds, and what each is built from.
enum NativeLibrary {
  resqlite,
  argon2;

  static NativeLibrary? byName(String? name) {
    for (final library in values) {
      if (library.name == name) return library;
    }
    return null;
  }

  /// Where `resqlite.gen`/`argon2.gen` put this library, and so where its
  /// sidecar goes.
  String libraryPath({required String zonaiRoot}) =>
      p.join(zonaiRoot, 'lib', 'gen', 'native', switch (this) {
        NativeLibrary.resqlite => switch (Platform.operatingSystem) {
          'macos' => 'libresqlite.dylib',
          'linux' => 'libresqlite.so',
          'windows' => 'resqlite.dll',
          final os => throw UnsupportedError(
            'Unsupported platform for resqlite: $os',
          ),
        },
        NativeLibrary.argon2 => argon2_ffi.defaultLibraryFileName,
      });

  Future<BuildInputs> inputs({
    required String repoRoot,
    required String targetArch,
  }) async => switch (this) {
    NativeLibrary.resqlite => _resqliteInputs(
      repoRoot: repoRoot,
      targetArch: targetArch,
    ),
    NativeLibrary.argon2 => await _argon2Inputs(
      zonaiRoot: p.join(repoRoot, 'apps', 'zonai'),
      targetArch: targetArch,
    ),
  };
}

/// resqlite's library is built by the submodule's own `tool/build_native.dart`
/// from C sources that live entirely inside the submodule, so the pin moving is
/// the thing this has to notice. Both roots hold nothing but source -- the
/// builder writes its output to `--output` and its scratch JSON to `tool/`,
/// neither of which is walked here.
///
/// The toolchain packages come from the committed workspace lockfile rather
/// than from `libs/resqlite/pubspec.yaml`: the pubspec's carets float, and it
/// is the *resolved* version of the thing that runs the C compiler that decides
/// the bytes. Naming the three explicitly, instead of hashing the whole
/// lockfile, keeps an unrelated dependency bump from invalidating a cache it
/// cannot have affected.
BuildInputs _resqliteInputs({
  required String repoRoot,
  required String targetArch,
}) {
  final submodule = p.join(repoRoot, 'libs', 'resqlite');
  return BuildInputs(
    roots: [
      p.join(submodule, 'native'),
      p.join(submodule, 'third_party', 'sqlite3mc'),
    ],
    files: [p.join(submodule, 'tool', 'build_native.dart')],
    facts: {
      ..._sharedFacts(targetArch),
      ...lockedVersions(p.join(repoRoot, 'pubspec.lock'), const [
        'code_assets',
        'hooks',
        'native_toolchain_c',
      ]),
    },
  );
}

/// argon2's library is libsodium, compiled by the `sodium` package's own build
/// hook (see tool/native/argon2_builder/pubspec.yaml). Nothing in this repo
/// holds that C source, so the resolved `sodium` version *is* the source
/// identity -- and `sodium: ^4.0.0` floats, so a new 4.x silently changes what
/// a from-source build would produce.
///
/// That version lives in the builder's own lockfile, which is gitignored, so a
/// fresh checkout has to resolve before it can be read. `dart pub get` here is
/// not wasted work: it is the same command `build_argon2_native.dart` runs as
/// its first step, so a `check` that goes on to rebuild pays for it once.
Future<BuildInputs> _argon2Inputs({
  required String zonaiRoot,
  required String targetArch,
}) async {
  final builderDir = p.join(zonaiRoot, 'tool', 'native', 'argon2_builder');
  final lockPath = p.join(builderDir, 'pubspec.lock');

  if (!File(lockPath).existsSync()) {
    final result = await Process.run('dart', [
      'pub',
      'get',
    ], workingDirectory: builderDir);
    if (result.exitCode != 0) {
      stderr.writeln('${result.stdout}\n${result.stderr}');
      throw StateError(
        'Could not resolve argon2_builder, so the sodium version backing the '
        'cached library is unknown.',
      );
    }
  }

  return BuildInputs(
    files: [
      p.join(zonaiRoot, 'tool', 'build_argon2_native.dart'),
      p.join(builderDir, 'pubspec.yaml'),
      p.join(builderDir, 'bin', 'argon2_builder.dart'),
    ],
    facts: {
      ..._sharedFacts(targetArch),
      ...lockedVersions(lockPath, const ['sodium']),
    },
  );
}

/// The Dart SDK compiles the build hooks and drives the C toolchain, so a
/// different SDK can produce different bytes from identical sources. The C
/// compiler itself has no equally cheap identifier and is not covered -- stated
/// at the top of this file rather than silently assumed away.
Map<String, String> _sharedFacts(String targetArch) => {
  'target': '${Platform.operatingSystem}-$targetArch',
  'dart': Platform.version,
};

/// The resolved versions of [packages], read from the lockfile at [lockPath].
///
/// A package that isn't in the lockfile is recorded as [missingVersion] rather
/// than dropped: a build-hook dependency disappearing is a change to how the
/// library gets built, and a fingerprint that quietly stopped covering it would
/// be the same silent staleness this file exists to catch. The sentinel is a
/// value a test can assert against, so a package renamed upstream shows up as a
/// failure here instead of as a fingerprint that no longer means anything.
Map<String, String> lockedVersions(String lockPath, List<String> packages) {
  final lock = loadYaml(File(lockPath).readAsStringSync());
  final locked = lock is YamlMap ? lock['packages'] : null;

  return {
    for (final name in packages)
      'pkg:$name': locked is YamlMap && locked[name] is YamlMap
          ? '${(locked[name] as YamlMap)['version']}'
          : missingVersion,
  };
}

/// Recorded by [lockedVersions] for a package the lockfile does not mention.
const missingVersion = '<missing>';

/// A stable digest of [inputs], with file paths reported relative to [root].
///
/// Paths are relativised and separator-normalised so the digest doesn't change
/// merely because CI checked out at a different absolute path or ran on
/// Windows. Contents are hashed per-file and the per-file lines sorted, so
/// directory listing order -- which the filesystem does not promise -- cannot
/// move the result.
///
/// A missing input throws rather than being skipped: a path that stops
/// resolving (a file renamed, a root moved) would otherwise silently shrink
/// what the fingerprint covers, which is exactly the failure this whole file
/// exists to prevent.
String fingerprintOf(BuildInputs inputs, {required String root}) {
  final lines = <String>[];

  for (final rootPath in inputs.roots) {
    final directory = Directory(rootPath);
    if (!directory.existsSync()) {
      throw StateError('Build-input root does not exist: $rootPath');
    }
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) continue;
      lines.add(_lineFor(entity, root: root));
    }
  }

  for (final filePath in inputs.files) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw StateError('Build-input file does not exist: $filePath');
    }
    lines.add(_lineFor(file, root: root));
  }

  lines.sort();

  for (final key in inputs.facts.keys.toList()..sort()) {
    lines.add('!$key=${inputs.facts[key]}');
  }

  return sha256.convert(utf8.encode(lines.join('\n'))).toString();
}

String _lineFor(File file, {required String root}) {
  final relative = p.url.joinAll(p.split(p.relative(file.path, from: root)));
  final digest = sha256.convert(file.readAsBytesSync()).toString();
  return '$relative $digest';
}

/// Records that [libraryPath] was built from [fingerprint].
void writeFingerprint(String libraryPath, String fingerprint) {
  File(buildStampPathFor(libraryPath))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('$fingerprint\n');
}

/// Why the library at [libraryPath] cannot be reused, or `null` if it can.
///
/// Returning the reason rather than a bool is what lets the caller print
/// something a CI log reader can act on -- "the cache is stale" and "the
/// download produced nothing" call for different responses, and collapsing
/// them to `false` throws that away.
String? checkFingerprint(String libraryPath, String expected) {
  if (!File(libraryPath).existsSync()) {
    return '$libraryPath is missing';
  }

  final stamp = File(buildStampPathFor(libraryPath));
  if (!stamp.existsSync()) {
    return '${stamp.path} is missing, so nothing vouches for '
        '${p.basename(libraryPath)}';
  }

  final recorded = stamp.readAsStringSync().trim();
  if (recorded != expected) {
    return '${p.basename(libraryPath)} was built from different sources '
        '(stamped $recorded, this checkout is $expected)';
  }

  return null;
}
