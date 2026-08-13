import 'package:zonai/src/domain/ipc_protocol_stamp.dart';
import 'package:zonai/src/domain/message_contract_stamp.dart';
import 'package:zonai/src/domain/project/project_binary.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_schema/src/handlers/messages/ipc_codec.dart';

import '../../deps.dart';

const _usage = '''
Usage: zonai compile [options]

Compile every worker executable into .zonai/executables/ and regenerate the
project entry. Does not produce a deployment bundle -- use `zonai build`.

Options:
  -h, --help            Show help information
      --flavor=<name>   Config flavor to compile with
      --release         Compile without Dart asserts
  -c, --config=<path>   Path to zonai.yml
''';

Future<int> compile([BuildSettings? buildSettings]) async {
  // `zonai build` reaches this with its own [buildSettings] and has already
  // handled `--help` itself, so only the bare `zonai compile` can be asking.
  if (buildSettings == null && args.help) {
    logger.info(_usage);
    return 1;
  }

  logger.info('Compiling all workers...');

  await Future.wait([
    operations.compile(buildSettings: buildSettings),
    extensions.compile(buildSettings: buildSettings),
    rules.compile(buildSettings: buildSettings),
    rateLimitsCompiler.compile(buildSettings: buildSettings),
    cronsCompiler.compile(buildSettings: buildSettings),
    config.compile(buildSettings: buildSettings),
  ]);

  // `zonai build` always rebuilds the host binary fresh right after this
  // returns (see build.dart), so it can never go stale. This only matters
  // for the dev host binary: `zonai compile` refreshes workers but, until
  // now, never touched the host -- so a worker recompiled against a wire
  // protocol change (see ipc_protocol_stamp.dart) or a message vocabulary
  // change (see message_contract_hash.dart) could silently outrun an
  // already-built host binary sitting on disk.
  if (buildSettings == null) {
    await _rebuildHostIfStale();
  }

  return 0;
}

Future<void> _rebuildHostIfStale() async {
  final hostPath = settings.compiledProjectBinaryPath;
  if (!fs.file(hostPath).existsSync()) return;

  final reason =
      _protocolStaleReason(hostPath) ?? _contractStaleReason(hostPath);
  if (reason == null) return;

  logger.info('$reason -- rebuilding host binary...');
  await ProjectBinary().compile();
}

String? _protocolStaleReason(String hostPath) {
  if (!isProtocolStale(hostPath, hostVersion: IpcCodec.version)) return null;

  return 'Host binary IPC protocol is stale '
      '(v${readProtocolStamp(hostPath)}, now v${IpcCodec.version})';
}

/// Unlike the protocol check, a *missing* contract stamp counts as stale here.
///
/// At spawn time an unstamped binary has to pass -- there is nothing to
/// compare, and refusing would break every ad-hoc build. But that also means
/// an unstamped host binary leaves the guard permanently inert. Rebuilding is
/// cheap and happens once: after it, the host carries a stamp and the check
/// has something to work with.
String? _contractStaleReason(String hostPath) {
  final expected = messageContractHash.value;
  if (expected == null) return null;

  final stamped = readMessageContractStamp(hostPath);
  if (stamped == expected) return null;

  if (stamped == null) {
    return 'Host binary carries no message contract stamp';
  }
  return 'Host binary message contract is stale';
}
