import 'dart:async';
import 'dart:convert';

import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/deps/stdin.dart';

class KeyboardInput {
  factory KeyboardInput() => _instance;
  KeyboardInput._() : _listeners = [];
  static KeyboardInput get _instance => KeyboardInput._();

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
          _callListeners(event);
        });

    cleanUp.add(stop);
  }

  void _callListeners(KeyboardEvent event) {
    for (final listener in _listeners) {
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
}

class KeyboardEvent {
  KeyboardEvent({required this.key});

  final String key;

  bool matches(String key) {
    if (key == this.key) return true;
    if (key.toLowerCase() == this.key.toLowerCase()) return true;

    return false;
  }
}
