import 'dart:async';

import 'package:zonai/src/deps/revali.dart';

import '../../../domain/constants.dart';
import '../../../native/resqlite_native.dart';
import '../../../utils/server_health.dart';

class ServerController {
  ServerController(this._onOutput, this._onStatusChange);

  final void Function(String line) _onOutput;
  final void Function(bool running) _onStatusChange;

  bool _attached = false;

  bool get isRunning => revali.isRunning || _attached;

  String get _startedMessage =>
      kIsCompiled ? 'Server started' : 'Connected to server';

  String get _stoppedMessage =>
      kIsCompiled ? 'Server stopped' : 'Disconnected from server';

  Future<void> probe() async {
    if (isRunning) return;
    if (await checkZonaiServerHealth()) {
      _attach(quiet: true);
    }
  }

  Future<void> start() async {
    if (isRunning) {
      _onOutput('Server is already running.');
      return;
    }

    if (await _waitForHealth()) {
      _attach();
      return;
    }

    if (!kIsCompiled) {
      _onOutput('No server found at ${serverHealthUrl()}.');
      _onOutput(
        'Start the dev server externally (e.g. sip r play serve), then try again.',
      );
      return;
    }

    await ensureResqliteNativeInstalled();

    final started = await revali.start(
      isDev: true,
      onStopped: () {
        _onOutput('Server stopped.');
        _onStatusChange(false);
      },
    );

    if (!started) {
      _onOutput('[error] Server failed to start.');
      return;
    }

    _onStatusChange(true);
    _onOutput(_startedMessage);
  }

  void stop() {
    if (_attached) {
      _attached = false;
      _onStatusChange(false);
      _onOutput(_stoppedMessage);
      return;
    }

    if (revali.isRunning) {
      _onOutput(_stoppedMessage);
      _onStatusChange(false);
      unawaited(revali.stop());
      return;
    }

    _onOutput('Server is not running.');
  }

  void dispose() {
    if (revali.isRunning && !_attached) {
      unawaited(revali.stop());
    }
  }

  void _attach({bool quiet = false}) {
    _attached = true;
    _onStatusChange(true);
    if (!quiet) _onOutput(_startedMessage);
  }

  Future<bool> _waitForHealth({
    int attempts = 30,
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    for (var i = 0; i < attempts; i++) {
      if (await checkZonaiServerHealth()) return true;
      if (i < attempts - 1) {
        await Future.delayed(delay);
      }
    }
    return false;
  }
}
