/// Thrown when a compiled worker subprocess exits or is killed before replying.
final class WorkerProcessFailedException implements Exception {
  const WorkerProcessFailedException({
    required this.workerName,
    required this.executablePath,
    this.exitCode,
    this.stderr = '',
    this.cause,
    this.stackTrace,
  });

  final String workerName;
  final String executablePath;
  final int? exitCode;
  final String stderr;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('$workerName worker failed');
    if (exitCode != null) {
      buffer.write(' (exit code: $exitCode)');
    }
    if (stderr.trim().isNotEmpty) {
      buffer.writeln();
      buffer.write(stderr.trim());
    }
    if (cause != null) {
      buffer.writeln();
      buffer.write(cause);
    }
    return buffer.toString();
  }
}
