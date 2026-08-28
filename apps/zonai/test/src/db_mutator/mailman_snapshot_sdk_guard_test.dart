import 'package:file/memory.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/db_mutator/worker_transport.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/executable_stop.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/mutations.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/snapshot_sdk_stamp.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart'
    hide logger;

import '../commands/db/admin/fake_zonai_db.dart' show fakeSettings;

/// Mailman must decide an `.aot` snapshot's SDK compatibility BEFORE it calls
/// `Isolate.spawnUri`, not around it.
///
/// The defect this file pins: `_tryStartIsolate` wrapped the spawn in a
/// `try`/`catch` and treated that as sufficient. It is not, and the half it
/// misses is the half that kills the host. Two measured failure modes on
/// macos-arm64:
///
/// - Same container format, different VM snapshot hash (3.12.0 host, 3.12.1
///   snapshot) raises `IsolateSpawnException: Wrong full snapshot version`.
///   The `catch` handles this one correctly and always has.
/// - Across a container-format change (a 3.12.x host handed a 3.13.x snapshot)
///   the process takes SIGABRT, exit 134, in `snapshot_utils.cc` before any
///   Dart code runs. There is no exception, the `catch` never executes, and
///   the host dies with every in-flight request.
///
/// A test cannot assert the second one directly -- reproducing it would take
/// this test process down with it, which is the whole point. So each test here
/// asserts the thing that makes it unreachable: whether `Isolate.spawnUri` was
/// called at all.
///
/// **How "did it spawn?" is observed.** The filesystem is a [MemoryFileSystem],
/// so every snapshot path here exists as far as Mailman's `existsSync` checks
/// are concerned and exists nowhere at all as far as the real
/// `Isolate.spawnUri` is concerned. A spawn that is attempted therefore always
/// fails, and failing is what logs `would not spawn` from the `catch`. That
/// line is the witness:
///
/// - present  -> control reached the `try` block and `Isolate.spawnUri` ran
/// - absent   -> the guard returned false first, and nothing was spawned
///
/// Asserting its absence alone would pass for the wrong reason if the snapshot
/// branch were never entered, so every test also asserts on the refusal
/// message, which only the SDK guard emits.
void main() {
  group('Mailman: the snapshot SDK guard', () {
    late MemoryFileSystem memoryFs;
    late List<String> warnings;

    /// Dart 3.12.0 on macos-arm64 -- the SDK CI pins, so this stands in for
    /// what a released host binary can load.
    const host3120 = '41be3daaabd524b8aa7423bc24584957';

    /// Dart 3.13.2 on macos-arm64. The other side of the container-format
    /// change, so this pair is the uncatchable one.
    const built3132 = '0451907c2eaa8467e848c0067bfe8ed4';

    Set<ScopedRef<Object>> overrides() => {
      settingsProvider.overrideWith(() => fakeSettings),
      fsProvider.overrideWith(() => memoryFs),
      loggerProvider.overrideWith(() => _RecordingLogger(warnings)),
      processProvider,
      cleanUpProvider,
      executableStopProvider,
      mutationsProvider,
    };

    setUp(() {
      memoryFs = MemoryFileSystem();
      warnings = [];
    });

    /// Drives one `_tryStartIsolate` and reports what it logged.
    ///
    /// `ping()` is the only public way in: it reaches `_start()`, which runs
    /// the isolate transport first because `workerTransportModeFromEnv()`
    /// answers `auto` with nothing in the environment. Whether the ping
    /// succeeds is not interesting and it never does here -- `executablePath`
    /// is deliberately left absent so that once the isolate path declines,
    /// `_startOnce` returns immediately rather than launching a worker
    /// process, and the ping falls out with nothing to send to.
    ///
    /// Every caller passes its own [snapshotPath]. Mailman de-duplicates these
    /// warnings in a `static` set that outlives an individual test, so two
    /// tests sharing a path would have the second one assert on silence that
    /// the first one caused.
    Future<void> ping({
      void Function()? prepare,
      String? snapshotPath,
      String? sourceEntryPath,
      String? hostVmHash,
      String? hostSdkVersion,
    }) async {
      await runScoped(() async {
        // Inside the scope, not beside it: `writeSnapshotSdkStamp` writes
        // through the scoped `fs`, and using it rather than hand-rolling the
        // sidecar keeps this test from having its own opinion about the file
        // format the guard reads.
        prepare?.call();

        final mailman = Mailman<Request, Response>(
          debugName: 'sdk-guard',
          // Never created on the memory filesystem: see above.
          executablePath: '/exes/db_operations.exe',
          snapshotPath: snapshotPath,
          sourceEntryPath: sourceEntryPath,
          hostVmHash: hostVmHash,
          hostSdkVersion: hostSdkVersion,
          fromJson: (_) => throw UnimplementedError('nothing replies here'),
        );

        await mailman.ping();
        await mailman.dispose();
      }, values: overrides());
    }

    /// The `catch` in `_tryStartIsolate` only says this once control has
    /// reached the `try`, so it is the witness for whether the spawn ran.
    final spawnWasAttempted = contains(contains('would not spawn'));
    final spawnWasNotAttempted = isNot(contains(contains('would not spawn')));

    test('declines a snapshot whose stamp names a different SDK, without '
        'spawning it', () async {
      const path = '/exes/mismatched.aot';

      await ping(
        prepare: () {
          fs.file(path).createSync(recursive: true);
          writeSnapshotSdkStamp(path, hash: built3132, version: '3.13.2');
        },
        snapshotPath: path,
        hostVmHash: host3120,
        hostSdkVersion: '3.12.0',
      );

      // The version strings are message text only -- the hashes are what was
      // compared -- but they are the whole reason a version string is carried
      // in the stamp at all, so the message has to actually use them.
      expect(
        warnings,
        contains(
          allOf(
            contains(path),
            contains('requires Dart 3.12.0'),
            contains('snapshot was compiled by 3.13.2'),
          ),
        ),
      );
      expect(warnings, spawnWasNotAttempted);
    });

    test('declines an unstamped snapshot, without spawning it', () async {
      const path = '/exes/unstamped.aot';

      await ping(
        prepare: () => fs.file(path).createSync(recursive: true),
        snapshotPath: path,
        hostVmHash: host3120,
        hostSdkVersion: '3.12.0',
      );

      // Unknown is refused here, inverting the protocol and contract guards.
      // The message has to say which of the two it is: "no stamp" and "wrong
      // stamp" call for different actions from whoever reads it.
      expect(
        warnings,
        contains(allOf(contains(path), contains('carries no `.sdk` stamp'))),
      );
      expect(warnings, spawnWasNotAttempted);
    });

    test('declines every snapshot when the host does not know its own hash, '
        'without spawning it', () async {
      const path = '/exes/unknown_host.aot';

      // A `zonai` compiled without `--define=ZONAI_VM_HASH=...`. Not an edge
      // case: it is every binary built before that define existed, and it
      // declines a snapshot that is in fact perfectly compatible. That cost is
      // the worker process, and it is the safe side of the trade.
      await ping(
        prepare: () {
          fs.file(path).createSync(recursive: true);
          writeSnapshotSdkStamp(path, hash: host3120, version: '3.12.0');
        },
        snapshotPath: path,
      );

      expect(
        warnings,
        contains(
          allOf(
            contains(path),
            contains('does not know which VM snapshot format it can load'),
          ),
        ),
      );
      expect(warnings, spawnWasNotAttempted);
    });

    test('spawns a snapshot whose stamp names this host exactly', () async {
      const path = '/exes/matching.aot';

      await ping(
        prepare: () {
          fs.file(path).createSync(recursive: true);
          writeSnapshotSdkStamp(path, hash: host3120, version: '3.12.0');
        },
        snapshotPath: path,
        hostVmHash: host3120,
        hostSdkVersion: '3.12.0',
      );

      // The load-bearing test of the four. Without it the other three pass
      // just as well against a guard that refuses unconditionally, which is a
      // real hazard here rather than a hypothetical one: the host's hash is a
      // `String.fromEnvironment` that is empty under `dart test`, so an
      // un-seamed guard refuses everything and looks entirely healthy.
      expect(warnings, spawnWasAttempted);
      expect(
        warnings,
        isNot(contains(contains('.sdk'))),
        reason: 'a matching stamp must not be refused',
      );
    });

    test('does not apply to the JIT source branch', () async {
      const sourcePath = '/gen/db_operations.dart';
      const snapshotPath = '/exes/ignored.aot';
      // The source branch is only reachable on the VM, and the guard's absence
      // from it means nothing if this test silently took the snapshot branch
      // instead.
      expect(
        isRunningOnDartVm,
        isTrue,
        reason: 'the JIT branch is unreachable if this is not the VM',
      );

      // A `.dart` entry is compiled by the VM that is already running, so the
      // host and the compiler are the same process and cannot skew apart. The
      // SDK stamp beside the snapshot describes an artifact this branch never
      // touches.
      await ping(
        prepare: () {
          fs.file(sourcePath).createSync(recursive: true);
          fs.file(snapshotPath).createSync(recursive: true);
          // Incompatible, and deliberately so: if the guard leaked out of the
          // snapshot branch it would refuse here too, and the stamp assertion
          // below is what would notice.
          writeSnapshotSdkStamp(
            snapshotPath,
            hash: built3132,
            version: '3.13.2',
          );
        },
        snapshotPath: snapshotPath,
        sourceEntryPath: sourcePath,
        hostVmHash: host3120,
        hostSdkVersion: '3.12.0',
      );

      expect(
        warnings,
        isNot(contains(contains('.sdk'))),
        reason: 'the SDK guard must not run on the source branch',
      );
      // `fromSnapshot` is false on this branch, so its spawn failure logs at
      // debug rather than warn -- asserting on the absence of the warn line
      // here would pass whether or not the spawn was attempted, which is why
      // it is the stamp message above that carries this test.
      expect(warnings, spawnWasNotAttempted);
    });
  });
}

class _RecordingLogger implements Logger {
  _RecordingLogger(this.warnings);

  final List<String> warnings;

  @override
  void warn(String message, {String? prefix}) => warnings.add(message);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
