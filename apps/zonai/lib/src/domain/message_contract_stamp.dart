import 'dart:io' as io;

import 'package:zonai/src/domain/constants.dart';

import '../deps/fs.dart';
import '../deps/message_contract_hash.dart';

/// Sidecar marker recording the [MessageContractHash] a compiled worker/host
/// binary was built against -- the sibling of `ipc_protocol_stamp.dart`, and
/// deliberately a second file rather than a second line in the first.
///
/// The two answer different questions and can disagree in either direction: a
/// worker can speak the right framing with the wrong vocabulary (#25) or the
/// wrong framing with the right vocabulary (`066b88b`). Keeping them apart
/// keeps each guard's message about one thing, and means the older stamp still
/// reads correctly next to a binary that predates this one.
///
/// The extension is *appended* rather than replaced -- `db_operations.exe`
/// stamps to `db_operations.exe.contract`, not `db_operations.contract`. The
/// `.protocol` stamp replaces it, and that scheme cannot tell
/// `db_operations.exe` from the `db_operations.aot` snapshot beside it: both
/// would claim the same sidecar, and the two are compiled by separate
/// invocations that have already been observed to diverge (see the note on
/// `compileArgs` in rules.dart). Two artifacts that can drift need two stamps.
String messageContractStampPathFor(String executablePath) =>
    '$executablePath.contract';

/// Records the contract this build was compiled against next to
/// [executablePath]. Call immediately after a successful `dart compile exe`,
/// beside `writeProtocolStamp`.
///
/// A no-op when the hash is unknown, and it deletes any stamp already there:
/// leaving a stale one behind would have the next spawn compare a fresh
/// executable against the contract of the build before it.
void writeMessageContractStamp(String executablePath) {
  final stampFile = fs.file(messageContractStampPathFor(executablePath));
  final hash = messageContractHash.value;

  if (hash == null) {
    if (stampFile.existsSync()) stampFile.deleteSync();
    return;
  }

  stampFile.parent.createSync(recursive: true);
  stampFile.writeAsStringSync(hash);
}

/// The contract [executablePath] was compiled against, or `null` when it
/// carries no stamp -- built before this mechanism existed, or compiled
/// outside `zonai compile`/`zonai build`.
String? readMessageContractStamp(String executablePath) {
  final stampFile = fs.file(messageContractStampPathFor(executablePath));
  if (!stampFile.existsSync()) return null;

  final contents = stampFile.readAsStringSync().trim();
  return contents.isEmpty ? null : contents;
}

/// The contract *this* process speaks, or `null` when it cannot be known.
///
/// Which of the two answers is right turns on how this host is running, and
/// getting it backwards would have the guard accuse the wrong side:
///
/// - A compiled host ([kIsCompiled]) froze its copy of `zonai_schema` at
///   compile time. Its own stamp is the only honest record of that; the
///   sources on disk have moved on independently and say nothing about it.
/// - A host running from source under `dart run` (the default `zonai serve`
///   path -- see `project_runtime.dart`) *is* the sources on disk, so hashing
///   them now is exact.
String? hostMessageContractHash() {
  if (kIsCompiled) {
    return readMessageContractStamp(io.Platform.resolvedExecutable);
  }
  return messageContractHash.value;
}

/// Whether the artifact at [executablePath] was definitely built against a
/// different contract than [hostHash].
///
/// `false` whenever either side is unknown. A missing stamp is the ordinary
/// state of an ad-hoc fixture and of every executable built before this
/// existed, and refusing those would break more than it caught. Known-and-
/// different is the only case that counts.
bool isMessageContractStale(
  String executablePath, {
  required String? hostHash,
}) {
  if (hostHash == null) return false;
  if (!fs.file(executablePath).existsSync()) return false;

  final stamped = readMessageContractStamp(executablePath);
  return stamped != null && stamped != hostHash;
}
