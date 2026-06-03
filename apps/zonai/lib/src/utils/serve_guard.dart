import 'dart:async';

import '../deps/logger.dart';

/// Runs async [body] during `serve`; errors are logged, not rethrown.
void catchErrors(Function() body) {
  try {
    final result = body();

    if (result is Future) {
      result.catchError(_logServeFutureError).ignore();
    }
  } catch (error, stack) {
    _logServeFutureError(error, stack);
  }
}

/// Runs [body] in a guarded zone so unhandled async errors during `serve` are
/// logged and do not terminate the process.
Future<void> runServeGuarded(Future<void> Function() body) async {
  await runZonedGuarded(body, _logServeZoneError);
}

/// Logs [error] from a fire-and-forget future started during `serve`.
void _logServeFutureError(Object error, StackTrace stack) {
  logger.error(
    'Unhandled error while serving (process continues)',
    error,
    stack,
  );
}

/// Zone [onError] callback for [runServeGuarded].
void _logServeZoneError(Object error, StackTrace stack) {
  logger.error(
    'Unhandled error while serving (process continues)',
    error,
    stack,
  );
}
