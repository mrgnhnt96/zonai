/// Thrown when a compiled worker executable is missing and must be built by the user.
final class ExecutableUnavailableException implements Exception {
  const ExecutableUnavailableException({
    required this.workerName,
    required this.executablePath,
    required this.message,
    this.stackTrace,
  });

  final String workerName;
  final String executablePath;
  final String message;
  final StackTrace? stackTrace;

  String get error => 'Worker $workerName is not compiled ($executablePath)';

  @override
  String toString() => message;
}
