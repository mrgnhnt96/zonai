import 'dart:async';
import 'dart:io' as io;

class Stdout {
  factory Stdout() => _instance ??= Stdout._();
  static Stdout? _instance;
  Stdout._() : _controller = StreamController<String>.broadcast() {
    _subscribe();
  }

  final StreamController<String> _controller;
  StreamSubscription<String>? _subscription;

  void _subscribe() {
    if (_subscription != null) return;

    _subscription = _controller.stream.listen((message) {
      io.stdout.write(message);
    });
  }

  void write(String message) {
    _controller.add(message);
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
