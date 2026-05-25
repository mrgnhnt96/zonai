import 'dart:io' as io;
import 'dart:async';

class Stdin {
  factory Stdin() => _instance ??= Stdin._();
  static Stdin? _instance;
  Stdin._()
    : _stream = io.stdin,
      _controller = StreamController<List<int>>.broadcast() {
    _subscribe();
  }

  final Stream<List<int>> _stream;
  StreamController<List<int>> _controller;
  StreamSubscription<List<int>>? _subscription;

  void _subscribe() {
    if (_subscription != null) return;

    _subscription = _stream.listen(_controller.add);
  }

  Stream<List<int>> get stream => _controller.stream;

  bool get hasTerminal => io.stdin.hasTerminal;

  set echoMode(bool value) {
    try {
      io.stdin.echoMode = value;
    } on io.StdinException {
      // CI and piped stdin may report a terminal but reject mode changes.
    }
  }

  set lineMode(bool value) {
    try {
      io.stdin.lineMode = value;
    } on io.StdinException {
      // CI and piped stdin may report a terminal but reject mode changes.
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
