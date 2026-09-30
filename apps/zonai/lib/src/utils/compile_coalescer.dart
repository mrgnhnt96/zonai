import 'dart:async';

import '../deps/logger.dart';

/// Turns a burst of file-watcher events into compiles that never overlap.
///
/// A watcher fires once per file, and a bulk change -- a `git checkout`, a
/// formatter, anything that touches every file in a directory -- fires one
/// event per file within milliseconds. Each worker used to answer every event
/// with its own `compile()`, so fourteen rule files meant fourteen concurrent
/// `dart compile exe` runs writing the same `.exe`: they clobbered each other
/// ("db_rules.exe: No such file or directory" while re-signing, "No 'main'
/// method found"), and the worker was left broken (reported against v0.10.0).
///
/// Three rules, the same ones `Migrate` already follows for its watcher:
///
///  * **Debounce.** A trigger restarts a short timer, and only the timer's
///    expiry compiles, so a burst becomes one compile.
///  * **One at a time.** A compile never starts while another is running.
///  * **Nothing lost.** A trigger that arrives during a compile marks one
///    follow-up, which runs when the current one finishes -- so an edit made
///    mid-compile is still compiled, however many triggers arrived.
final class CompileCoalescer {
  CompileCoalescer(
    this._compile, {
    required this.label,
    this.debounce = const Duration(milliseconds: 300),
  });

  final Future<Object?> Function() _compile;

  /// Names the worker in the one log line a coalesced burst produces.
  final String label;

  final Duration debounce;

  Timer? _timer;
  bool _running = false;
  bool _followUp = false;
  bool _cancelled = false;

  /// Asks for a compile. Many calls close together produce one.
  void trigger() {
    if (_cancelled) return;
    _timer?.cancel();
    _timer = Timer(debounce, _fire);
  }

  /// Stops any pending compile and ignores later triggers. A compile already
  /// running finishes, but no follow-up starts after it.
  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    _followUp = false;
  }

  Future<void> _fire() async {
    _timer = null;
    if (_cancelled) return;
    if (_running) {
      _followUp = true;
      return;
    }

    _running = true;
    try {
      logger.info('Detected changes in $label, recompiling...');
      await _compile();
    } catch (e, stack) {
      logger.error('Failed to recompile $label', e, stack);
    } finally {
      _running = false;
      if (_followUp && !_cancelled) {
        _followUp = false;
        unawaited(_fire());
      }
    }
  }
}
