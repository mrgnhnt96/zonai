import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/logger.dart';

class Kill {
  Kill() : _listeners = [] {
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
  }

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
    exit(0);
  }

  void _dispose() async {
    __killSubscription?.cancel();
    __killSubscription = null;
    _callListeners();
  }
}
