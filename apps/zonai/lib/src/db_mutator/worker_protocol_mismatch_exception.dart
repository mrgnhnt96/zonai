import '../domain/ipc_protocol_stamp.dart';

/// Thrown when a worker's compiled wire-protocol version doesn't match this
/// host's, so [Mailman] refuses to spawn it rather than let the mismatched
/// pair crash deep inside stream parsing (see `ipc_protocol_stamp.dart`).
final class WorkerProtocolMismatchException implements Exception {
  const WorkerProtocolMismatchException({
    required this.workerName,
    required this.executablePath,
    required this.hostVersion,
    required this.workerVersion,
  });

  /// Builds the exception for [executablePath] iff its protocol stamp is
  /// present and disagrees with [hostVersion]. Returns `null` (no mismatch)
  /// when the stamp matches, or when it's missing entirely -- a worker built
  /// before this stamping existed, or compiled outside `zonai compile`/
  /// `zonai build` (e.g. an ad-hoc test fixture), is unknown, not wrong.
  static WorkerProtocolMismatchException? forStamp({
    required String workerName,
    required String executablePath,
    required int hostVersion,
  }) {
    final stamped = readProtocolStamp(executablePath);
    if (stamped == null || stamped == hostVersion) return null;

    return WorkerProtocolMismatchException(
      workerName: workerName,
      executablePath: executablePath,
      hostVersion: hostVersion,
      workerVersion: stamped,
    );
  }

  final String workerName;
  final String executablePath;
  final int hostVersion;
  final int workerVersion;

  String get message =>
      '$workerName worker ($executablePath) speaks IPC protocol '
      'v$workerVersion but this host speaks v$hostVersion.\n'
      'The host binary and this worker were compiled at different times '
      'across a wire-format change. Run `zonai compile` -- it detects a '
      'stale dev host binary and rebuilds it automatically. If this host is '
      'a deployed `zonai build` bundle instead (compile only refreshes '
      'workers there, not the bundle), rebuild with `zonai build` and '
      'redeploy.\n'
      'See https://docs.zonai.dev/cli/upgrading';

  @override
  String toString() => message;
}
