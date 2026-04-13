import 'dart:io' as io;
import 'dart:async';

import 'package:io/io.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';

class Stdin {
  factory Stdin() => _instance;
  Stdin._()
    : _stream = sharedStdIn,
      _controller = StreamController<List<int>>.broadcast() {
    _subscribe();
  }
  static Stdin get _instance => Stdin._();

  final Stream<List<int>> _stream;
  StreamController<List<int>> _controller;
  StreamSubscription<List<int>>? _subscription;

  void _subscribe() {
    if (_subscription != null) return;

    _subscription = _stream.listen(_controller.add);

    cleanUp.add(_dispose);
  }

  Stream<List<int>> get stream => _controller.stream;

  bool get hasTerminal => io.stdin.hasTerminal;
  set echoMode(bool value) => io.stdin.echoMode = value;
  set lineMode(bool value) => io.stdin.lineMode = value;

  void _dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
