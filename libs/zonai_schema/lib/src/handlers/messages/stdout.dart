import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

class Stdout {
  factory Stdout() => _instance ??= Stdout._();
  static Stdout? _instance;
  Stdout._() : _controller = StreamController<Uint8List>.broadcast() {
    _subscribe();
  }

  final StreamController<Uint8List> _controller;
  StreamSubscription<Uint8List>? _subscription;

  void _subscribe() {
    if (_subscription != null) return;

    _subscription = _controller.stream.listen((frame) {
      io.stdout.add(frame);
    });
  }

  /// Writes one framed IPC message to process stdout.
  void writeFrame(Uint8List frame) {
    _controller.add(frame);
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
