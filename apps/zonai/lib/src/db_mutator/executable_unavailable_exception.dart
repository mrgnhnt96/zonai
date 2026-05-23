/// Thrown when a compiled worker executable is missing and must be built by the user.
final class ExecutableUnavailableException implements Exception {
  const ExecutableUnavailableException({
    required this.workerName,
    required this.executablePath,
    required this.message,
  });

  final String workerName;
  final String executablePath;
  final String message;

  @override
  String toString() => message;
}
