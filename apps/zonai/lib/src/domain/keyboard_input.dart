import 'dart:async';
import 'dart:convert';
import 'dart:io' show stdout;

import '../deps/clean_up.dart';
import '../deps/args.dart';
import '../deps/logger.dart';
import '../deps/stdin.dart';

class KeyboardInput {
  KeyboardInput() : _listeners = [] {
    cleanUp.add(unlockInput);
  }

  StreamSubscription<KeyboardEvent>? __subscription;
  var _cursorHidden = false;

  final List<void Function(KeyboardEvent)> _listeners;

  void addListener(void Function(KeyboardEvent) listener) {
    if (args.release) return;

    _listeners.add(listener);
  }

  void onKey(String key, void Function() callback) {
    if (args.release) return;

    _listeners.add((event) {
      if (event.matches(key)) {
        callback();
      }
    });
  }

  void removeListener(void Function(KeyboardEvent) listener) {
    _listeners.remove(listener);
  }

  void watch() {
    if (args.release) return;

    if (__subscription != null) return;

    lockInput();

    __subscription = stdin.stream
        .map((event) {
          var key = utf8.decode(event).toLowerCase().trim();
          if (key.isEmpty && event.length == 1) {
            key = '${event[0]}';
          }
          return KeyboardEvent(key: key);
        })
        .listen((event) {
          logger.debug('Keyboard input: $event');
          _callListeners(event);
        });

    cleanUp.add(stop);
  }

  void _callListeners(KeyboardEvent event) {
    final listeners = _listeners.toList();
    for (final listener in listeners) {
      try {
        listener(event);
      } catch (e) {
        logger.debug('Error calling listener: $e');
      }
    }
  }

  void stop() {
    __subscription?.cancel();
    __subscription = null;
    _listeners.clear();
  }

  void lockInput() {
    if (args.release) return;

    if (stdout.hasTerminal) {
      stdout.write('\x1B[?25l');
      _cursorHidden = true;
    }

    if (!stdin.hasTerminal) return;

    stdin.echoMode = false;
    stdin.lineMode = false;
  }

  void unlockInput() {
    if (args.release) return;

    if (_cursorHidden && stdout.hasTerminal) {
      stdout.write('\x1B[?25h');
      _cursorHidden = false;
    }

    if (!stdin.hasTerminal) return;

    stdin.echoMode = true;
    stdin.lineMode = true;
  }

  /// Restores stdin without writing to stdout so nocterm can take over the terminal.
  void releaseForAlternateApp() {
    if (args.release) return;

    if (!stdin.hasTerminal) return;

    stdin.echoMode = true;
    stdin.lineMode = true;
  }
}

class KeyboardEvent {
  KeyboardEvent({required this.key});

  final String key;

  bool matches(String key) {
    if (key == this.key) return true;
    if (key.toLowerCase() == this.key.toLowerCase()) return true;

    return false;
  }

  @override
  String toString() {
    return key;
  }
}
