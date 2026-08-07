import 'package:zonai_schema/src/handlers/messages/ipc_codec.dart';

import '../deps/fs.dart';

/// Sidecar marker recording the [IpcCodec.version] a compiled worker/host
/// binary was built against.
///
/// `066b88b` swapped the host<->worker wire format from newline-JSON to
/// framed MessagePack with zero backward compatibility: a worker compiled
/// after that change cannot talk to a host binary compiled before it (or
/// vice versa). Nothing else on disk records which wire version a given
/// executable speaks -- [IpcCodec.version] itself is only known in-process,
/// and `pubspec.lock`-based version checks (see `schema_version_check.dart`)
/// are a no-op for the `zonai_schema` path dependency this monorepo (and any
/// project pointing at a local checkout) actually uses. This stamp is the
/// only durable signal that survives across separate `zonai compile`/
/// `zonai build` invocations, so staleness can be caught before a mismatched
/// pair is ever wired together.
String protocolStampPathFor(String executablePath) {
  final name = fs.path.basenameWithoutExtension(executablePath);
  return fs.path.join(fs.path.dirname(executablePath), '$name.protocol');
}

/// Records the current [IpcCodec.version] next to a just-compiled
/// [executablePath]. Call this immediately after a successful `dart compile
/// exe` of a worker or the host/project binary.
void writeProtocolStamp(String executablePath) {
  final stampFile = fs.file(protocolStampPathFor(executablePath));
  stampFile.parent.createSync(recursive: true);
  stampFile.writeAsStringSync('${IpcCodec.version}');
}

/// Reads the wire-protocol version [executablePath] was compiled against, or
/// `null` if no stamp exists (e.g. a pre-existing build from before this
/// mechanism, or an ad-hoc/test-fixture executable compiled outside the
/// normal `zonai compile`/`zonai build` path) or the stamp is unparseable.
int? readProtocolStamp(String executablePath) {
  final stampFile = fs.file(protocolStampPathFor(executablePath));
  if (!stampFile.existsSync()) return null;
  return int.tryParse(stampFile.readAsStringSync().trim());
}

/// Whether the compiled artifact at [executablePath] is definitely stale
/// relative to [hostVersion] -- i.e. it exists and its stamp disagrees.
/// `false` (not stale) when the file is missing or unstamped: there's
/// nothing to compare against, so it's unknown rather than wrong.
bool isProtocolStale(String executablePath, {required int hostVersion}) {
  if (!fs.file(executablePath).existsSync()) return false;
  final stamped = readProtocolStamp(executablePath);
  return stamped != null && stamped != hostVersion;
}
