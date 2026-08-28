import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/domain/vm_snapshot_hash.dart';

const _hashA = '41be3daaabd524b8aa7423bc24584957';
const _hashB = 'ace654289f5abc240509fc941453ebc5';

/// Writes [contents] as raw bytes at [path], so the fixtures say exactly which
/// bytes surround a candidate run -- what bounds a run is the whole question.
void _writeBinary(String path, String contents) {
  fs.file(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(contents.codeUnits);
}

/// A `dartaotruntime` shaped like the real one: binary noise on both sides of
/// a single hash.
String _runtimeBytes(String body) => '\x00\x7fELF\x01\x02$body\x00\x00pad\x00';

void _memoryTest(String description, void Function() body) {
  test(description, () {
    runScoped(body, values: {fsProvider.overrideWith(MemoryFileSystem.new)});
  });
}

void main() {
  group('vmSnapshotHashOfFile', () {
    _memoryTest('returns the value when exactly one 32-hex run exists', () {
      _writeBinary('/sdk/dartaotruntime', _runtimeBytes(_hashA));

      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), _hashA);
    });

    _memoryTest('returns null when there is no 32-hex run', () {
      _writeBinary('/sdk/dartaotruntime', _runtimeBytes('not a hash at all'));

      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), isNull);
    });

    _memoryTest('returns null when two distinct 32-hex runs exist', () {
      // The whole reason `null` is not "no hash": the file has a hash in it,
      // and picking one of the two would be a guess.
      _writeBinary('/sdk/dartaotruntime', _runtimeBytes('$_hashA\x00$_hashB'));

      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), isNull);
    });

    _memoryTest('one distinct value repeated is still one answer', () {
      _writeBinary('/sdk/dartaotruntime', _runtimeBytes('$_hashA\x00$_hashA'));

      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), _hashA);
    });

    _memoryTest('uppercase hex is not a match', () {
      _writeBinary('/sdk/dartaotruntime', _runtimeBytes(_hashA.toUpperCase()));

      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), isNull);
    });

    _memoryTest('a 31-character hex run is not a match', () {
      _writeBinary('/sdk/dartaotruntime', _runtimeBytes(_hashA.substring(1)));

      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), isNull);
    });

    _memoryTest('a 33-character hex run is not a match', () {
      // Not just "the first 32 of it": the extra character has to disqualify
      // the whole run, or every long hex blob in a binary becomes a candidate.
      _writeBinary('/sdk/dartaotruntime', _runtimeBytes('${_hashA}f'));

      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), isNull);
    });

    _memoryTest('a 33-character run does not mask a real one', () {
      _writeBinary(
        '/sdk/dartaotruntime',
        _runtimeBytes('${_hashB}f\x00$_hashA'),
      );

      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), _hashA);
    });

    _memoryTest('finds a run that straddles the streaming chunk boundary', () {
      // The scan reads 64 KiB at a time, so a hash sitting across the seam is
      // the case a naive per-chunk scan silently loses.
      final lead = 'x' * (64 * 1024 - 8);
      _writeBinary('/sdk/dartaotruntime', _runtimeBytes('$lead\x00$_hashA'));

      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), _hashA);
    });

    _memoryTest('a run ending at end-of-file is still a match', () {
      _writeBinary('/sdk/dartaotruntime', '\x00\x00$_hashA');

      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), _hashA);
    });

    _memoryTest('returns null for a file that is not there', () {
      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), isNull);
    });

    _memoryTest('returns null for an empty file', () {
      _writeBinary('/sdk/dartaotruntime', '');

      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), isNull);
    });
  });

  group('sdkVmSnapshotHash', () {
    _memoryTest('reads the dartaotruntime beside the given dart', () {
      _writeBinary('/sdk/bin/dart', 'the dart launcher, not a runtime');
      _writeBinary('/sdk/bin/dartaotruntime', _runtimeBytes(_hashA));

      expect(sdkVmSnapshotHash('/sdk/bin/dart'), _hashA);
    });

    _memoryTest('returns null when the sibling runtime is absent', () {
      _writeBinary('/sdk/bin/dart', 'the dart launcher, not a runtime');

      expect(sdkVmSnapshotHash('/sdk/bin/dart'), isNull);
    });

    _memoryTest('returns null when the sibling runtime is ambiguous', () {
      _writeBinary('/sdk/bin/dart', 'the dart launcher, not a runtime');
      _writeBinary('/sdk/bin/dartaotruntime', _runtimeBytes('$_hashA-$_hashB'));

      expect(sdkVmSnapshotHash('/sdk/bin/dart'), isNull);
    });

    _memoryTest('follows a symlinked dart into its real SDK', () {
      // The shape every Dart version manager installs: a `dart` on PATH
      // pointing into a versioned SDK that holds the runtime.
      _writeBinary('/sdk/bin/dart', 'the dart launcher, not a runtime');
      _writeBinary('/sdk/bin/dartaotruntime', _runtimeBytes(_hashA));
      fs.directory('/shims').createSync(recursive: true);
      fs.link('/shims/dart').createSync('/sdk/bin/dart');

      expect(sdkVmSnapshotHash('/shims/dart'), _hashA);
    });

    _memoryTest('returns null for an empty executable path', () {
      expect(sdkVmSnapshotHash(''), isNull);
    });
  });

  group('against a real SDK', () {
    // The one test that proves the format assumption rather than restating it:
    // a genuine dartaotruntime holds exactly one lowercase 32-hex run. Skipped
    // rather than failed where none is reachable, since a null here would be
    // "could not look", not "nothing there".
    final resolved = io.Platform.resolvedExecutable;
    final runtime = p.join(p.dirname(resolved), 'dartaotruntime');
    final reachable = io.File(runtime).existsSync();

    test(
      'this SDK\'s dartaotruntime yields exactly one hash',
      () {
        final hash = runScoped(
          () => vmSnapshotHashOfFile(runtime),
          values: {fsProvider.overrideWith(LocalFileSystem.new)},
        );

        expect(hash, matches(RegExp(r'^[0-9a-f]{32}$')));
      },
      skip: reachable ? null : 'no dartaotruntime beside $resolved',
    );

    test(
      'sdkVmSnapshotHash agrees with reading the runtime directly',
      () {
        final viaSdk = runScoped(
          () => sdkVmSnapshotHash(resolved),
          values: {fsProvider.overrideWith(LocalFileSystem.new)},
        );
        final direct = runScoped(
          () => vmSnapshotHashOfFile(runtime),
          values: {fsProvider.overrideWith(LocalFileSystem.new)},
        );

        expect(viaSdk, isNotNull);
        expect(viaSdk, direct);
      },
      skip: reachable ? null : 'no dartaotruntime beside $resolved',
    );
  });

  group('outside an fs scope', () {
    // Found by running the real thing before trusting the memory-filesystem
    // tests: `fs` throws a bare StateError, not a FileSystemException, so a
    // catch narrowed to file errors let it through. Both entry points run in
    // front of a spawn, where a throw is the failure they exist to prevent.
    test('vmSnapshotHashOfFile returns null instead of throwing', () {
      expect(vmSnapshotHashOfFile('/sdk/dartaotruntime'), isNull);
    });

    test('sdkVmSnapshotHash returns null instead of throwing', () {
      expect(sdkVmSnapshotHash('/sdk/bin/dart'), isNull);
    });
  });

  group('host defines', () {
    // Not baked in when the suite runs on the VM, which is the case every
    // caller has to treat as UNKNOWN rather than as mismatch.
    test('are null when nothing was baked in', () {
      expect(hostVmSnapshotHash, isNull);
      expect(hostDartSdkVersion, isNull);
    });
  });
}
