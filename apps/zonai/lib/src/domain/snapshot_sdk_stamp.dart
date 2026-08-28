import '../deps/fs.dart';

/// Sidecar marker recording which Dart SDK compiled an `.aot` worker snapshot
/// -- the third of the sidecars beside `ipc_protocol_stamp.dart` and
/// `message_contract_stamp.dart`, and the only one whose unknown case refuses.
///
/// The three guard three independent ways a host and the snapshot it loads can
/// disagree, and any of them can be wrong while the other two are right: the
/// wire framing (`.protocol`), the message vocabulary (`.contract`), and the
/// VM snapshot format the two were built for (`.sdk`). Splitting them keeps
/// each guard's message about one thing, and lets an older stamp still read
/// correctly next to a binary compiled before this one existed.
///
/// The extension is *appended* rather than replaced -- `db_operations.aot`
/// stamps to `db_operations.aot.sdk`, not `db_operations.sdk`. The `.protocol`
/// stamp replaces it, and that scheme cannot tell `db_operations.exe` from the
/// `db_operations.aot` beside it: both would claim the same sidecar, and the
/// two are compiled by separate invocations that have already been observed to
/// diverge (see the note on `compileArgs` in rules.dart). Two artifacts that
/// can drift need two stamps -- and here the `.exe` is not even loaded by the
/// host's VM, so the `.aot`'s SDK is the only one that matters.
///
/// ## Why unknown means DO NOT SPAWN, unlike its two siblings
///
/// [isProtocolStale] and [isMessageContractStale] both answer `false` -- not
/// stale -- when either side is missing or unstamped, because unknown is not
/// the same as wrong, and refusing every pre-existing or ad-hoc artifact would
/// break more than it caught. This one inverts that, deliberately, and the
/// inversion is the whole point of the file.
///
/// The two costs are not comparable. A false negative here is an uncatchable
/// `SIGABRT` (exit 134) inside `snapshot_utils.cc` when a 3.12.x host loads a
/// 3.13.x snapshot: it happens before any Dart code runs, mailman's
/// `try`/`catch` around `Isolate.spawnUri` never executes, and the host process
/// dies taking every in-flight request with it. A false positive is that
/// mailman falls back to the worker process, which serves identically -- the
/// only thing lost is in-process dispatch. A guard whose miss is a crash and
/// whose over-reach is a slightly slower dispatch belongs on the safe side, so
/// every way of failing to establish compatibility answers "incompatible":
/// missing stamp, unreadable stamp, missing snapshot, and a host that does not
/// know its own hash.
///
/// That last one is the case worth naming, because it is not an edge case. A
/// `zonai` compiled without `--define=ZONAI_VM_HASH=...` -- a stock binary from
/// before that define existed -- has a `null` [hostVmSnapshotHash], and under
/// this rule it declines every snapshot it is offered. That is the intended
/// behaviour and it is not silent degradation to nothing: such a host still
/// serves every request through the worker process.
///
/// ## Why the hash and not the version
///
/// Compatibility follows the VM snapshot hash, not semver -- 3.12.1 and 3.12.2
/// share a hash and spawn each other's snapshots, 3.12.0 does not despite
/// sharing their minor. See `vm_snapshot_hash.dart`, which owns the measurement
/// and is the one way to obtain a hash. The version string written beside the
/// hash here is message text only, so a refusal can say "built by Dart 3.13.2,
/// this host needs 3.12.0" instead of printing two hex strings at somebody. It
/// is never compared, and a version that disagrees with the hash is the version
/// being wrong.

/// The path of the sidecar recording which SDK built the snapshot at
/// [snapshotPath]. Appended, extension and all; see the note above.
String snapshotSdkStampPathFor(String snapshotPath) => '$snapshotPath.sdk';

/// What a `.sdk` sidecar says: the VM snapshot hash of the SDK that compiled
/// the snapshot, and that SDK's version string when it was known.
///
/// [hash] is the comparison. [version] is for message text and may be `null`
/// even in a perfectly good stamp -- an SDK whose hash could be read but whose
/// version could not is still fully usable as a guard.
typedef SnapshotSdkStamp = ({String hash, String? version});

/// Records that the snapshot at [snapshotPath] was compiled by the SDK with
/// [hash] and [version]. Call immediately after a successful `dart compile
/// aot-snapshot`, beside `writeMessageContractStamp`.
///
/// Writes two lines, hash first, so the value the guard compares is at a fixed
/// position and a future third line cannot displace it. [version] is omitted
/// rather than written empty when it is unknown.
///
/// A `null` [hash] is a no-op that also deletes any stamp already there.
/// Leaving the old one would have the next spawn compare a fresh snapshot
/// against the SDK of the build before it -- which, given that a match here
/// authorises loading foreign machine code into this process, is the one
/// outcome worth going out of the way to prevent. What is left behind is an
/// unstamped snapshot, which [isSnapshotSdkIncompatible] refuses; the cost of
/// that refusal is the worker process, not a failure.
void writeSnapshotSdkStamp(
  String snapshotPath, {
  required String? hash,
  required String? version,
}) {
  final stampFile = fs.file(snapshotSdkStampPathFor(snapshotPath));

  if (hash == null) {
    if (stampFile.existsSync()) stampFile.deleteSync();
    return;
  }

  stampFile.parent.createSync(recursive: true);
  stampFile.writeAsStringSync(
    version == null || version.isEmpty ? '$hash\n' : '$hash\n$version\n',
  );
}

/// What the sidecar beside [snapshotPath] says, or `null` when it cannot say.
///
/// `null` covers a snapshot with no stamp at all -- built before this mechanism
/// existed, or compiled outside `zonai compile`/`zonai build` -- and a stamp
/// whose first line is empty. Callers must treat `null` as *unknown*, and
/// unknown here means do not spawn; see [isSnapshotSdkIncompatible].
///
/// The hash is returned exactly as written rather than validated against the
/// shape of a VM snapshot hash. Only equality with the host's own hash decides
/// anything, and a malformed stamp cannot equal a real hash, so validating it
/// would add a second way to say the same "no" while giving a reader two
/// different reasons to chase.
SnapshotSdkStamp? readSnapshotSdkStamp(String snapshotPath) {
  final stampFile = fs.file(snapshotSdkStampPathFor(snapshotPath));
  if (!stampFile.existsSync()) return null;

  final lines = stampFile.readAsStringSync().split('\n');
  final hash = lines.first.trim();
  if (hash.isEmpty) return null;

  final version = lines.length > 1 ? lines[1].trim() : '';
  return (hash: hash, version: version.isEmpty ? null : version);
}

/// Whether the snapshot at [snapshotPath] must NOT be handed to
/// `Isolate.spawnUri` by a host whose own VM snapshot hash is [hostHash].
///
/// `true` unless compatibility is positively established -- the inversion of
/// [isProtocolStale] and [isMessageContractStale], for the reasons at the top
/// of this file. Every one of these answers `true`:
///
/// - [hostHash] is `null`: the host cannot say what it can load. That is a
///   binary compiled without `--define=ZONAI_VM_HASH=...`, and it declines
///   every snapshot rather than guessing.
/// - The snapshot is not there. Nothing can vouch for a file that does not
///   exist, and an orphaned stamp left beside a deleted snapshot must not be
///   able to speak for one.
/// - The snapshot carries no readable stamp.
/// - The stamp names a different hash. This is the case the guard exists for.
///
/// Only a present snapshot, with a readable stamp, naming exactly the host's
/// own hash, is `false`.
bool isSnapshotSdkIncompatible(
  String snapshotPath, {
  required String? hostHash,
}) {
  if (hostHash == null) return true;
  if (!fs.file(snapshotPath).existsSync()) return true;

  final stamped = readSnapshotSdkStamp(snapshotPath);
  if (stamped == null) return true;

  return stamped.hash != hostHash;
}
