import 'dart:math' as math;

import 'package:zonai_sync/src/remote.dart' show FailureKind;

/// Exponential backoff for entries that failed for a retryable reason.
final class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 8,
    this.base = const Duration(seconds: 15),
    this.cap = const Duration(minutes: 15),
  });

  /// Attempts (spent only by [FailureKind.server]-class failures) after which
  /// an entry is dead-lettered. Being offline never spends an attempt.
  final int maxAttempts;
  final Duration base;
  final Duration cap;

  Duration delayAfter(int attempts) {
    final ms = base.inMilliseconds * math.pow(2, math.max(0, attempts - 1));
    return Duration(milliseconds: math.min(ms.toInt(), cap.inMilliseconds));
  }
}
