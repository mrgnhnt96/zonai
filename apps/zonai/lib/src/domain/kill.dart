import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import '../deps/clean_up.dart';
import '../deps/keyboard_input.dart';
import '../deps/logger.dart';

class Kill {
  Kill() : _listeners = [], _lifeline = Completer<void>() {
    final stream = Platform.isWindows
        ? ProcessSignal.sigint.watch()
        : StreamGroup.merge([
            ProcessSignal.sigterm.watch(),
            ProcessSignal.sigint.watch(),
          ]);

    __killSubscription = stream.listen((event) {
      force();
    });

    cleanUp.add(_dispose);
    listenForKeyboardInput();
  }

  final Completer<void> _lifeline;
  StreamSubscription<ProcessSignal>? __killSubscription;

  final List<void Function()> _listeners;

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _callListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        logger.debug('Error calling listener: $e');
      }
    }
  }

  /// kill the current process
  void force() async {
    logger.debug('Killing process');
    _dispose();
    await cleanUp.run();
    if (!_lifeline.isCompleted) {
      _lifeline.complete();
    }
    exit(0);
  }

  void _dispose() async {
    __killSubscription?.cancel();
    __killSubscription = null;
    _callListeners();
  }

  void listenForKeyboardInput() {
    keyboardInput.onKey('q', force);
  }

  /// Cancels signal handlers so an alternate TUI (e.g. nocterm) can own SIGINT/SIGTERM.
  void suspendSignals() {
    __killSubscription?.cancel();
    __killSubscription = null;
  }

  Future<void> wait() async => await _lifeline.future;
}
