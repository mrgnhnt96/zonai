import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/snapshot_sdk_stamp.dart';

/// A real 32-hex VM snapshot hash, so the fixtures look like what the guard
/// actually compares: Dart 3.12.0 on macos-arm64, the SDK CI pins.
const _hash3120 = '41be3daaabd524b8aa7423bc24584957';

/// Dart 3.13.2 on macos-arm64 -- the other side of the container-format change
/// that takes the host down with SIGABRT rather than a catchable exception.
const _hash3132 = '0451907c2eaa8467e848c0067bfe8ed4';

void main() {
  late MemoryFileSystem memoryFs;

  Set<ScopedRef<dynamic>> overrides() => {
    fsProvider.overrideWith(() => memoryFs),
  };

  setUp(() {
    memoryFs = MemoryFileSystem();
  });

  /// A snapshot that exists on disk, which several branches need before the
  /// stamp is even consulted.
  void placeSnapshot(String path) => fs.file(path).createSync(recursive: true);

  group('stamp path', () {
    test('appends .sdk to the snapshot, extension and all', () {
      runScoped(() {
        expect(
          snapshotSdkStampPathFor('/exes/db_operations.aot'),
          '/exes/db_operations.aot.sdk',
        );
      }, values: overrides());
    });

    // An `.exe` and the `.aot` beside it are separate compiles that have
    // diverged before, so they cannot share one sidecar.
    test('an executable and its sibling snapshot get separate stamps', () {
      runScoped(() {
        expect(
          snapshotSdkStampPathFor('/exes/db_operations.aot'),
          isNot(snapshotSdkStampPathFor('/exes/db_operations.exe')),
        );

        writeSnapshotSdkStamp(
          '/exes/db_operations.aot',
          hash: _hash3120,
          version: '3.12.0',
        );

        expect(
          readSnapshotSdkStamp('/exes/db_operations.aot')?.hash,
          _hash3120,
        );
        expect(readSnapshotSdkStamp('/exes/db_operations.exe'), isNull);
      }, values: overrides());
    });
  });

  group('write and read', () {
    test('read round-trips what write wrote', () {
      runScoped(() {
        writeSnapshotSdkStamp(
          '/exes/db_operations.aot',
          hash: _hash3120,
          version: '3.12.0',
        );

        expect(readSnapshotSdkStamp('/exes/db_operations.aot'), (
          hash: _hash3120,
          version: '3.12.0',
        ));
      }, values: overrides());
    });

    test('write creates parent directories as needed', () {
      runScoped(() {
        writeSnapshotSdkStamp(
          '/nested/deep/db_operations.aot',
          hash: _hash3120,
          version: '3.12.0',
        );

        expect(
          fs.file('/nested/deep/db_operations.aot.sdk').existsSync(),
          isTrue,
        );
      }, values: overrides());
    });

    // Hash first, at a fixed position, so a future third line cannot displace
    // the one value the guard compares.
    test('writes two lines, hash first', () {
      runScoped(() {
        writeSnapshotSdkStamp(
          '/exes/db_operations.aot',
          hash: _hash3120,
          version: '3.12.0',
        );

        expect(
          fs.file('/exes/db_operations.aot.sdk').readAsStringSync().split('\n'),
          containsAllInOrder([_hash3120, '3.12.0']),
        );
      }, values: overrides());
    });

    test('read returns null when no stamp exists', () {
      runScoped(() {
        expect(readSnapshotSdkStamp('/exes/db_operations.aot'), isNull);
      }, values: overrides());
    });

    test('read returns null for an empty stamp', () {
      runScoped(() {
        fs.file('/exes/db_operations.aot.sdk')
          ..createSync(recursive: true)
          ..writeAsStringSync('   \n');

        expect(readSnapshotSdkStamp('/exes/db_operations.aot'), isNull);
      }, values: overrides());
    });

    // A hash whose version could not be read is still a fully usable guard --
    // only the message text is poorer for it.
    test('a hash-only stamp reads back with a null version', () {
      runScoped(() {
        writeSnapshotSdkStamp(
          '/exes/db_operations.aot',
          hash: _hash3120,
          version: null,
        );

        expect(readSnapshotSdkStamp('/exes/db_operations.aot'), (
          hash: _hash3120,
          version: null,
        ));
      }, values: overrides());
    });

    test('an empty version is read back as null, not as an empty string', () {
      runScoped(() {
        writeSnapshotSdkStamp(
          '/exes/db_operations.aot',
          hash: _hash3120,
          version: '',
        );

        expect(
          readSnapshotSdkStamp('/exes/db_operations.aot')?.version,
          isNull,
        );
      }, values: overrides());
    });

    // Leaving the old one would have the next spawn compare a fresh snapshot
    // against the SDK of the build before it -- and a match here authorises
    // loading foreign machine code into this process.
    test('write clears a stale stamp when the hash is unknown', () {
      runScoped(() {
        fs.file('/exes/db_operations.aot.sdk')
          ..createSync(recursive: true)
          ..writeAsStringSync('$_hash3120\n3.12.0\n');

        writeSnapshotSdkStamp(
          '/exes/db_operations.aot',
          hash: null,
          version: '3.12.0',
        );

        expect(fs.file('/exes/db_operations.aot.sdk').existsSync(), isFalse);
      }, values: overrides());
    });

    test('write with an unknown hash is a no-op when there is no stamp', () {
      runScoped(() {
        writeSnapshotSdkStamp(
          '/exes/db_operations.aot',
          hash: null,
          version: null,
        );

        expect(fs.file('/exes/db_operations.aot.sdk').existsSync(), isFalse);
      }, values: overrides());
    });
  });

  group('isSnapshotSdkIncompatible', () {
    test('false only when a stamped, present snapshot names the host hash', () {
      runScoped(() {
        placeSnapshot('/exes/db_operations.aot');
        writeSnapshotSdkStamp(
          '/exes/db_operations.aot',
          hash: _hash3120,
          version: '3.12.0',
        );

        expect(
          isSnapshotSdkIncompatible(
            '/exes/db_operations.aot',
            hostHash: _hash3120,
          ),
          isFalse,
        );
      }, values: overrides());
    });

    // The case the guard exists for: 3.12.0 host, 3.13.2 snapshot, which is a
    // container-format change and so an uncatchable SIGABRT if it were spawned.
    test('true when the stamp names a different SDK', () {
      runScoped(() {
        placeSnapshot('/exes/db_operations.aot');
        writeSnapshotSdkStamp(
          '/exes/db_operations.aot',
          hash: _hash3132,
          version: '3.13.2',
        );

        expect(
          isSnapshotSdkIncompatible(
            '/exes/db_operations.aot',
            hostHash: _hash3120,
          ),
          isTrue,
        );
      }, values: overrides());
    });

    // The first of the two unknowns, and the inversion of what the `.protocol`
    // and `.contract` guards do with the same situation.
    test('true when the snapshot carries no stamp', () {
      runScoped(() {
        placeSnapshot('/exes/db_operations.aot');

        expect(
          isSnapshotSdkIncompatible(
            '/exes/db_operations.aot',
            hostHash: _hash3120,
          ),
          isTrue,
        );
      }, values: overrides());
    });

    test('true when the stamp exists but is unreadable', () {
      runScoped(() {
        placeSnapshot('/exes/db_operations.aot');
        fs.file('/exes/db_operations.aot.sdk').writeAsStringSync('\n3.12.0\n');

        expect(
          isSnapshotSdkIncompatible(
            '/exes/db_operations.aot',
            hostHash: _hash3120,
          ),
          isTrue,
        );
      }, values: overrides());
    });

    // The second unknown: an unstamped stock binary, which does not know what
    // it can load and so declines everything rather than guessing.
    test('true when the host does not know its own hash', () {
      runScoped(() {
        placeSnapshot('/exes/db_operations.aot');
        writeSnapshotSdkStamp(
          '/exes/db_operations.aot',
          hash: _hash3120,
          version: '3.12.0',
        );

        expect(
          isSnapshotSdkIncompatible('/exes/db_operations.aot', hostHash: null),
          isTrue,
        );
      }, values: overrides());
    });

    test('true when the snapshot does not exist', () {
      runScoped(() {
        expect(
          isSnapshotSdkIncompatible(
            '/exes/db_operations.aot',
            hostHash: _hash3120,
          ),
          isTrue,
        );
      }, values: overrides());
    });

    // An orphaned stamp must not be able to speak for a snapshot that is no
    // longer there -- without the existence check this one reads as compatible.
    test('true when a matching stamp outlives the snapshot it described', () {
      runScoped(() {
        writeSnapshotSdkStamp(
          '/exes/db_operations.aot',
          hash: _hash3120,
          version: '3.12.0',
        );

        expect(fs.file('/exes/db_operations.aot').existsSync(), isFalse);
        expect(
          isSnapshotSdkIncompatible(
            '/exes/db_operations.aot',
            hostHash: _hash3120,
          ),
          isTrue,
        );
      }, values: overrides());
    });
  });
}
