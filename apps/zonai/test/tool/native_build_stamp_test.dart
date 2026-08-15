import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/src/native_build_stamp.dart';
import '../support/temp_directory.dart';

/// This fingerprint is what stands between CI and embedding a native library
/// built from sources that are no longer in the checkout. The bug it replaces
/// was an existence check that passed for *any* file of the right name, so the
/// cases below are written the same way round: each one changes something a
/// build genuinely depends on and asserts the fingerprint noticed.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('native_build_stamp_test');
    _write(root, 'src/a.c', 'int a(void) { return 1; }');
    _write(root, 'src/nested/b.h', '#define B 1');
    _write(root, 'builder.dart', 'void main() {}');
  });

  tearDown(() => deleteTempDirectory(root));

  BuildInputs inputs({
    Map<String, String> facts = const {'target': 'linux-x64'},
  }) {
    return BuildInputs(
      roots: [p.join(root.path, 'src')],
      files: [p.join(root.path, 'builder.dart')],
      facts: facts,
    );
  }

  String fingerprint({
    Map<String, String> facts = const {'target': 'linux-x64'},
  }) {
    return fingerprintOf(inputs(facts: facts), root: root.path);
  }

  group('fingerprintOf', () {
    test('is stable across repeated computation', () {
      expect(fingerprint(), fingerprint());
    });

    test('changes when a source file under a root changes', () {
      // The headline case: the resqlite submodule pin moves, so the C sources
      // differ, so the cached library no longer corresponds to them.
      final before = fingerprint();
      _write(root, 'src/a.c', 'int a(void) { return 2; }');

      expect(fingerprint(), isNot(before));
    });

    test('changes when a file is added under a root', () {
      final before = fingerprint();
      _write(root, 'src/c.c', 'int c(void) { return 3; }');

      expect(fingerprint(), isNot(before));
    });

    test('changes when a file is removed from a root', () {
      final before = fingerprint();
      File(p.join(root.path, 'src', 'nested', 'b.h')).deleteSync();

      expect(fingerprint(), isNot(before));
    });

    test('changes when a listed file changes', () {
      final before = fingerprint();
      _write(root, 'builder.dart', 'void main() { print("different"); }');

      expect(fingerprint(), isNot(before));
    });

    test('changes when a fact changes', () {
      // Facts carry the target triple, the SDK version and resolved build-hook
      // package versions -- inputs with no file in the tree to hash.
      expect(
        fingerprint(facts: const {'pkg:sodium': '4.0.0'}),
        isNot(fingerprint(facts: const {'pkg:sodium': '4.1.0'})),
      );
    });

    test('distinguishes targets, so one arch cannot vouch for another', () {
      expect(
        fingerprint(facts: const {'target': 'macos-arm64'}),
        isNot(fingerprint(facts: const {'target': 'macos-x64'})),
      );
    });

    test('is unchanged by where the tree is checked out', () {
      // CI runs from a different absolute path than any developer, and Windows
      // separates paths differently again. Either one changing the digest
      // would mean the cache never hits and the whole mechanism is dead
      // weight, so paths are hashed relative and separator-normalised.
      final before = fingerprint();

      final moved = Directory.systemTemp.createTempSync('native_build_stamp_2');
      addTearDown(() => deleteTempDirectory(moved));
      for (final relative in ['src/a.c', 'src/nested/b.h', 'builder.dart']) {
        _write(
          moved,
          relative,
          File(
            p.join(root.path, p.joinAll(p.posix.split(relative))),
          ).readAsStringSync(),
        );
      }

      expect(
        fingerprintOf(
          BuildInputs(
            roots: [p.join(moved.path, 'src')],
            files: [p.join(moved.path, 'builder.dart')],
            facts: const {'target': 'linux-x64'},
          ),
          root: moved.path,
        ),
        before,
      );
    });

    test('throws when a listed file has gone missing', () {
      // Skipping it instead would quietly shrink what the fingerprint covers
      // -- the same silent staleness this exists to catch, one level up.
      File(p.join(root.path, 'builder.dart')).deleteSync();

      expect(() => fingerprint(), throwsStateError);
    });

    test('throws when a root has gone missing', () {
      Directory(p.join(root.path, 'src')).deleteSync(recursive: true);

      expect(() => fingerprint(), throwsStateError);
    });
  });

  group('checkFingerprint', () {
    late String libraryPath;

    setUp(() {
      libraryPath = p.join(root.path, 'libresqlite.so');
    });

    test('accepts a library stamped with the current fingerprint', () {
      File(libraryPath).writeAsStringSync('bytes');
      writeFingerprint(libraryPath, fingerprint());

      expect(checkFingerprint(libraryPath, fingerprint()), isNull);
    });

    test('refuses a library whose sources have since changed', () {
      // The regression proper. The library file is present and correctly named
      // -- which is all the old `--check`/`[ -f ]` ever asked -- but it was
      // built before this edit, so its bytes are stale.
      File(libraryPath).writeAsStringSync('bytes');
      writeFingerprint(libraryPath, fingerprint());
      _write(root, 'src/a.c', 'int a(void) { return 2; }');

      expect(
        checkFingerprint(libraryPath, fingerprint()),
        contains('built from different sources'),
      );
    });

    test('refuses an unstamped library', () {
      // Every artifact built before this mechanism existed looks like this.
      File(libraryPath).writeAsStringSync('bytes');

      expect(
        checkFingerprint(libraryPath, fingerprint()),
        contains('nothing vouches for'),
      );
    });

    test('refuses a missing library, naming it', () {
      expect(checkFingerprint(libraryPath, fingerprint()), contains('missing'));
    });

    test('refuses a stamp whose library is gone', () {
      writeFingerprint(libraryPath, fingerprint());

      expect(checkFingerprint(libraryPath, fingerprint()), contains('missing'));
    });

    test('tolerates trailing whitespace in the stamp', () {
      File(libraryPath).writeAsStringSync('bytes');
      File(
        buildStampPathFor(libraryPath),
      ).writeAsStringSync('${fingerprint()}\n\n');

      expect(checkFingerprint(libraryPath, fingerprint()), isNull);
    });
  });

  _realRepoGroup();
}

/// Everything above works on a synthetic tree, so it stays true no matter what
/// the real specs point at. These point them at the actual repo, because the
/// way this mechanism dies quietly is a path or package name that stops
/// resolving: `<missing>` for every package, or roots that were renamed, still
/// produce a stable fingerprint and still pass every test above -- while
/// covering nothing.
void _realRepoGroup() {
  final repoRoot = _repoRoot();

  group('the real build-input specs', () {
    test(
      'resqlite names inputs that exist and versions that resolve',
      () async {
        final inputs = await NativeLibrary.resqlite.inputs(
          repoRoot: repoRoot,
          targetArch: 'arm64',
        );

        for (final root in inputs.roots) {
          expect(
            Directory(root).existsSync(),
            isTrue,
            reason: '$root is listed as a build-input root but does not exist',
          );
        }
        for (final file in inputs.files) {
          expect(
            File(file).existsSync(),
            isTrue,
            reason: '$file is listed as a build input but does not exist',
          );
        }
        expect(
          inputs.facts,
          containsPair('pkg:native_toolchain_c', isNot(missingVersion)),
          reason:
              'the package that drives the C toolchain must be pinned by the '
              'fingerprint, or a toolchain bump silently keeps the cache',
        );
        expect(
          inputs.facts,
          containsPair('pkg:code_assets', isNot(missingVersion)),
        );
        expect(inputs.facts, containsPair('pkg:hooks', isNot(missingVersion)));
      },
    );

    test('resqlite hashes the C sources the library is built from', () async {
      final inputs = await NativeLibrary.resqlite.inputs(
        repoRoot: repoRoot,
        targetArch: 'arm64',
      );

      // Named explicitly: these are the files whose bytes become the library,
      // and a root that stopped reaching them is the failure being guarded
      // against. Walking the roots here proves the walk reaches them.
      final walked = [
        for (final root in inputs.roots)
          ...Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .map((f) => p.relative(f.path, from: repoRoot)),
      ];

      expect(
        walked,
        contains(p.join('libs', 'resqlite', 'native', 'resqlite.c')),
      );
      expect(
        walked,
        contains(
          p.join(
            'libs',
            'resqlite',
            'third_party',
            'sqlite3mc',
            'sqlite3mc_amalgamation.c',
          ),
        ),
      );
    });

    test('argon2 names inputs that exist and resolves sodium', () async {
      final inputs = await NativeLibrary.argon2.inputs(
        repoRoot: repoRoot,
        targetArch: 'arm64',
      );

      for (final file in inputs.files) {
        expect(
          File(file).existsSync(),
          isTrue,
          reason: '$file is listed as a build input but does not exist',
        );
      }
      expect(
        inputs.facts,
        containsPair('pkg:sodium', isNot(missingVersion)),
        reason:
            'sodium is the only identity libsodium has here -- nothing in '
            'this repo holds that C source',
      );
    });

    test('both libraries fingerprint without throwing', () async {
      for (final library in NativeLibrary.values) {
        final inputs = await library.inputs(
          repoRoot: repoRoot,
          targetArch: 'arm64',
        );

        expect(
          fingerprintOf(inputs, root: repoRoot),
          hasLength(64),
          reason: '${library.name} should produce a sha256 hex digest',
        );
      }
    });
  });
}

/// Walks up from the test file to the directory holding the workspace lockfile.
///
/// `dart test` runs with the package root as the working directory, but that is
/// a convention rather than a promise, and this test needs the *repo* root two
/// levels above it. Finding it by a file that only exists there survives being
/// run from somewhere else.
String _repoRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File(p.join(directory.path, 'pubspec.lock')).existsSync() &&
        Directory(p.join(directory.path, 'libs', 'resqlite')).existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not find the repo root from ${Directory.current}',
      );
    }
    directory = parent;
  }
}

void _write(Directory root, String relativePath, String contents) {
  File(p.join(root.path, p.joinAll(p.posix.split(relativePath))))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);
}
