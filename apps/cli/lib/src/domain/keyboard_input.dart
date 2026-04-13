import 'dart:async';
import 'dart:convert';
import 'dart:io' show stdout;

import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/deps/stdin.dart';

class KeyboardInput {
  factory KeyboardInput() => _instance;
  static KeyboardInput get _instance => KeyboardInput._();
  KeyboardInput._() : _listeners = [] {
    lockInput();
    cleanUp.add(unlockInput);
  }

  StreamSubscription<KeyboardEvent>? __subscription;

  final List<void Function(KeyboardEvent)> _listeners;

  void addListener(void Function(KeyboardEvent) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(KeyboardEvent) listener) {
    _listeners.remove(listener);
  }

  void watch() {
    if (__subscription != null) return;

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
    if (!stdin.hasTerminal) return;

    stdin.echoMode = false;
    stdin.lineMode = false;
    // hide cursor
    stdout.write('\x1B[?25l');
  }

  void unlockInput() {
    if (!stdin.hasTerminal) return;

    stdin.echoMode = true;
    stdin.lineMode = true;
    // show cursor
    stdout.write('\x1B[?25h');
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
