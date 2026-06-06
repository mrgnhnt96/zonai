import 'dart:async';

import '../components/dev_header.dart';

/// Tracks concurrent dev TUI actions for the header badges.
class DevActionTracker {
  DevActionTracker({
    required this.onChanged,
    this.successDuration = const Duration(seconds: 1),
  });

  final void Function() onChanged;
  final Duration successDuration;

  final _actions = <String, DevActionBadgeState>{};
  final _successTimers = <String, Timer>{};

  Map<String, DevActionBadgeState> get actions => Map.unmodifiable(_actions);

  bool get isBusy =>
      _actions.values.any((state) => state == DevActionBadgeState.running);

  void start(String label) {
    _successTimers.remove(label)?.cancel();
    _actions[label] = DevActionBadgeState.running;
    onChanged();
  }

  void succeed(String label) {
    if (!_actions.containsKey(label)) return;
    _actions[label] = DevActionBadgeState.succeeded;
    onChanged();
    _successTimers[label]?.cancel();
    _successTimers[label] = Timer(successDuration, () {
      _successTimers.remove(label);
      _actions.remove(label);
      onChanged();
    });
  }

  void finish(String label) {
    _successTimers.remove(label)?.cancel();
    _actions.remove(label);
    onChanged();
  }

  void fail(String label) {
    _successTimers.remove(label)?.cancel();
    _actions.remove(label);
    onChanged();
  }

  Future<T> run<T>(
    String label,
    Future<T> Function() action, {
    bool showSuccess = true,
    bool Function(T result)? isSuccess,
  }) async {
    start(label);
    try {
      final result = await action();
      final success = isSuccess?.call(result) ?? true;
      if (success) {
        if (showSuccess) {
          succeed(label);
        } else {
          finish(label);
        }
      } else {
        fail(label);
      }
      return result;
    } catch (_) {
      fail(label);
      rethrow;
    }
  }

  void dispose() {
    for (final timer in _successTimers.values) {
      timer.cancel();
    }
    _successTimers.clear();
    _actions.clear();
  }
}
