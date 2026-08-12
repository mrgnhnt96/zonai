import '../domain/message_contract_stamp.dart';

/// Thrown when a worker was compiled against a different *message contract*
/// than this host speaks, so [Mailman] refuses to spawn it.
///
/// The sibling of `WorkerProtocolMismatchException`, and intentionally the
/// same shape. That one answers "can these two binaries talk at all?"; this
/// one answers "do they mean the same things?". A worker that fails this check
/// would start happily, pass the protocol check, and then throw inside a
/// request handler -- which reaches an end user as a 5xx with a Dart stack
/// trace instead of reaching the operator as something they can act on.
final class WorkerContractMismatchException implements Exception {
  const WorkerContractMismatchException({
    required this.workerName,
    required this.executablePath,
    required this.hostContract,
    required this.workerContract,
  });

  /// Builds the exception for [executablePath] iff its contract stamp is
  /// present and disagrees with [hostContract]. Returns `null` when they
  /// match, when the worker carries no stamp, or when [hostContract] is
  /// unknown -- see [isMessageContractStale] for why unknown passes.
  static WorkerContractMismatchException? forStamp({
    required String workerName,
    required String executablePath,
    required String? hostContract,
  }) {
    if (hostContract == null) return null;

    final stamped = readMessageContractStamp(executablePath);
    if (stamped == null || stamped == hostContract) return null;

    return WorkerContractMismatchException(
      workerName: workerName,
      executablePath: executablePath,
      hostContract: hostContract,
      workerContract: stamped,
    );
  }

  final String workerName;
  final String executablePath;
  final String hostContract;
  final String workerContract;

  /// Enough of a sha256 to tell two apart in a log line. The full hash is in
  /// the `.contract` sidecar for anyone who needs to diff them.
  static String _short(String hash) =>
      hash.length <= 12 ? hash : hash.substring(0, 12);

  String get message =>
      '$workerName worker ($executablePath) was built against message '
      'contract ${_short(workerContract)} but this host speaks '
      '${_short(hostContract)}.\n'
      'The wire format still matches -- what changed is the vocabulary inside '
      'it: an enum value, a request field, or a payload key that this worker '
      'was compiled before. Upgrading `zonai_schema`, pulling a newer CLI, or '
      'restoring an older build directory all do this. Left alone the worker '
      'would start and then fail part-way through a request.\n'
      'Run `zonai compile` -- it rebuilds every worker, and a stale dev host '
      'binary with them. If this host is a deployed `zonai build` bundle '
      'instead (compile only refreshes workers there, not the bundle), '
      'rebuild with `zonai build` and redeploy.\n'
      'See https://docs.zonai.dev/cli/upgrading';

  @override
  String toString() => message;
}
