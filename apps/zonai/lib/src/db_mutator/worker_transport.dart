// dart format width=100
import 'dart:io' show Platform;

import 'package:path/path.dart' as p;

/// How Mailman talks to ops/rules workers.
enum WorkerTransportMode {
  /// Prefer isolate (AOT snapshot or JIT source); fall back to process.
  auto,

  /// Always use framed MessagePack over stdin/stdout to the `.exe`.
  process,

  /// Prefer isolate; if spawn fails, fall back to process.
  isolate,
}

WorkerTransportMode workerTransportModeFromEnv() {
  final raw = Platform.environment['ZONAI_WORKER_TRANSPORT']?.trim().toLowerCase();
  return switch (raw) {
    'process' || 'exe' || 'pipe' => WorkerTransportMode.process,
    'isolate' || 'sendport' => WorkerTransportMode.isolate,
    _ => WorkerTransportMode.auto,
  };
}

bool get isRunningOnDartVm {
  final name = p.basename(Platform.resolvedExecutable).toLowerCase();
  return name == 'dart' || name == 'dart.exe';
}
