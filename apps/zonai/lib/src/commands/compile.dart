import 'package:zonai/src/domain/ipc_protocol_stamp.dart';
import 'package:zonai/src/domain/project/project_binary.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai_schema/src/handlers/messages/ipc_codec.dart';

import '../../deps.dart';

Future<int> compile([BuildSettings? buildSettings]) async {
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
  // protocol change (see ipc_protocol_stamp.dart) could silently outrun an
  // already-built host binary sitting on disk.
  if (buildSettings == null) {
    await _rebuildHostIfProtocolStale();
  }

  return 0;
}

Future<void> _rebuildHostIfProtocolStale() async {
  final hostPath = settings.compiledProjectBinaryPath;
  if (!isProtocolStale(hostPath, hostVersion: IpcCodec.version)) return;

  logger.info(
    'Host binary IPC protocol is stale (v${readProtocolStamp(hostPath)}, '
    'now v${IpcCodec.version}) -- rebuilding...',
  );
  await ProjectBinary().compile();
}
