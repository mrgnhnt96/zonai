/// Caps how many [run] calls can be concurrently in flight. Unlike a queue,
/// admitted calls are not serialized against each other -- excess callers
/// past [maxConcurrent] fail immediately via [onSaturated] instead of
/// waiting for a turn.
final class ConcurrencyGate {
  ConcurrencyGate({required this.maxConcurrent, required this.onSaturated});

  final int maxConcurrent;
  final Object Function() onSaturated;

  var _pending = 0;

  /// Calls currently admitted and not yet completed.
  int get pending => _pending;

  Future<T> run<T>(Future<T> Function() body) async {
    if (_pending >= maxConcurrent) {
      throw onSaturated();
    }
    _pending++;
    try {
      return await body();
    } finally {
      _pending--;
    }
  }
}
