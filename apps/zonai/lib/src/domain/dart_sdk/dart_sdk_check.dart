import 'package:meta/meta.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/vm_snapshot_hash.dart';
import 'package:zonai/src/utils/dart_sdk.dart';

/// Tells a developer their Dart SDK has drifted from the one this binary was
/// built with, before they build something that cannot run.
///
/// A compiled zonai host loads its `.aot` workers through `Isolate.spawnUri`.
/// Those snapshots are produced by whatever SDK `DartExecutable.resolve()`
/// finds on the developer's machine, while the host carries the runtime of the
/// SDK that compiled *it* -- CI's pinned one for a released binary. Nothing
/// makes those the same SDK, and when they differ across a snapshot
/// container-format change the host takes SIGABRT inside `snapshot_utils.cc`
/// before any Dart code runs. There is no exception to catch and no fallback
/// to reach; the process is simply gone. Saying so up front is the only thing
/// that survives that.
///
/// ## Hashes, never versions
///
/// The comparison is [hostVmSnapshotHash] against
/// [sdkVmSnapshotHash] -- 32 hex characters on each side, equal or not.
/// Compatibility does not follow semver: 3.13.1 and 3.13.2 share a hash and
/// must not be reported as out of sync, while 3.12.0 and 3.12.1 do not share
/// one and must be, despite sharing a minor. A version *string* appears in the
/// message and nowhere else, so a reader gets "Dart 3.12.0" rather than two
/// hex strings; it is never compared. See vm_snapshot_hash.dart for the
/// measurements.
///
/// ## Unknown is silence, not alarm
///
/// Either side being unreadable -- an unstamped binary, an SDK with no
/// `dartaotruntime` beside it, no Dart SDK installed at all -- returns `null`
/// and says nothing.
///
/// That is the opposite of what a guard sitting in front of the spawn itself
/// should do, and deliberately so, because the cost of being wrong is
/// opposite. A spawn-time guard's mistake is a crash it could have prevented,
/// so it is entitled to refuse on doubt. This check's mistake is a false alarm
/// telling a developer their perfectly good toolchain is broken, aimed at a
/// human who cannot verify it and will either act on it or learn to ignore
/// every warning this CLI prints. Between those, silence is the cheaper error.
///
/// ## Severity
///
/// `zonai compile` and `zonai build` refuse with an exit code: they are the
/// only commands that write an `.aot`, so they are the last moment before a
/// bad artifact exists on disk. Every other command warns and proceeds -- once
/// per process, which is what the single call site in `zonai_runner.dart`
/// makes true.
class DartSdkCheck {
  const DartSdkCheck({String? hostHash, String? hostVersion})
    : _hostHash = hostHash,
      _hostVersion = hostVersion;

  /// Testability seams only -- production always falls back to what was baked
  /// into this binary. Both are `String.fromEnvironment` constants, which are
  /// empty in any `dart test` run, so without these a test could never reach
  /// the comparison at all. Nullable fields rather than constructor defaults
  /// keep this `const`-constructible, as with `SchemaVersionCheck`.
  final String? _hostHash;
  final String? _hostVersion;

  String? get hostHash => _hostHash ?? hostVmSnapshotHash;
  String? get hostVersion => _hostVersion ?? hostDartSdkVersion;

  /// Best-effort, guarded entry point for `zonai_runner.dart`'s `run()`.
  ///
  /// Returns an exit code only where a mismatch is worth refusing on; `null`
  /// means proceed, whether or not anything was printed.
  ///
  /// No-ops entirely when [kIsCompiled] is false: running from source, the
  /// host *is* the Dart VM that would compile the workers, so there is no
  /// second SDK to disagree with. Honors `--no-dart-sdk-check`.
  Future<int?> ensure() async {
    if (!kIsCompiled) {
      return null;
    }

    if (isDisabled) {
      return null;
    }

    // [check] would answer `null` for an unstamped host anyway, but only after
    // resolving the SDK -- and resolving runs `dart --version` in a
    // subprocess. This runs in front of every command, so the case with
    // nothing to compare should cost nothing.
    if (hostHash == null) {
      return null;
    }

    final dartExecutable = await _resolveDartExecutable();
    if (dartExecutable == null) {
      return null;
    }

    return check(dartExecutable);
  }

  /// Whether `--no-dart-sdk-check` turned this off.
  ///
  /// Both spellings, because `Args.parse` files `--no-x` under `x` as `false`
  /// rather than under `no-x` as `true`, and only one of those is obvious from
  /// the flag as typed. Exposed so a test can reach the escape hatch: every
  /// path through [ensure] is unreachable under `dart test`, where
  /// [kIsCompiled] is `false`.
  @visibleForTesting
  bool get isDisabled =>
      args['no-dart-sdk-check'] == true || args['dart-sdk-check'] == false;

  /// The `dart` that would compile this project's workers, or `null` when the
  /// machine has none.
  ///
  /// `DartExecutable.resolve()` throws when it finds no SDK, and that is the
  /// ordinary state of a deployed bundle: a released binary serving on a box
  /// with no Dart installed compiles nothing and is in no danger. Taking the
  /// command down there would be this check causing the outage it exists to
  /// prevent.
  Future<String?> _resolveDartExecutable() async {
    try {
      return await resolveDartExecutable();
    } on Object {
      return null;
    }
  }

  /// The real logic behind [ensure], without the [kIsCompiled]/CLI-flag guard
  /// -- exposed so tests can exercise it directly.
  ///
  /// [dartExecutablePath] is whatever `DartExecutable.resolve()` returned; the
  /// SDK it names is the one that would compile this project's workers.
  @visibleForTesting
  int? check(String dartExecutablePath) {
    final host = hostHash;
    if (host == null) {
      return null;
    }

    final sdk = sdkVmSnapshotHash(dartExecutablePath);
    if (sdk == null) {
      return null;
    }

    if (host == sdk) {
      return null;
    }

    return _report(
      hostHash: host,
      sdkHash: sdk,
      sdkVersion: sdkDartVersion(dartExecutablePath),
    );
  }

  /// Whether the command being run is one that can write an `.aot`.
  bool get _writesSnapshots => switch (args.path) {
    ['compile', ...] || ['build', ...] => true,
    _ => false,
  };

  int? _report({
    required String hostHash,
    required String sdkHash,
    required String? sdkVersion,
  }) {
    final builtWith = switch (hostVersion) {
      null => 'a different Dart SDK',
      final version => 'Dart $version',
    };
    final youAreOn = sdkVersion ?? 'an SDK that does not name its version';

    // Both hashes, in full, on their own line: they are the comparison, and a
    // report that only paraphrases them cannot be checked by the person
    // reading it -- least of all when one of the version strings is missing
    // and the sentence above has gone vague.
    final body =
        'zonai was built with $builtWith; you are on $youAreOn.\n'
        'Compiled workers will not load in-process '
        '(this binary: $hostHash, your SDK: $sdkHash).\n'
        'Switch SDKs, or set dartSdkPath in zonai.yaml.';

    if (!_writesSnapshots) {
      logger.warn(
        '$body\n'
        'Pass --no-dart-sdk-check to silence this.',
      );
      return null;
    }

    logger.error(
      '$body\n'
      'Pass --no-dart-sdk-check to build anyway.',
    );
    return 1;
  }
}
