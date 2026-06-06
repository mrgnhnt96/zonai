import 'dart:convert';
import 'dart:io';

import '../../../domain/constants.dart';
import '../../../utils/server_health.dart';
import 'subprocess_runner.dart';

class ServerController {
  ServerController(this._onOutput, this._onStatusChange);

  final void Function(String line) _onOutput;
  final void Function(bool running) _onStatusChange;

  Process? _process;
  bool _attached = false;

  bool get isRunning => _process != null || _attached;

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

    final (exe, args) = resolveZonaiCommand(['serve']);

    try {
      _process = await Process.start(exe, args);
    } catch (e) {
      _onOutput('[error] Failed to start server: $e');
      return;
    }

    _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onOutput);
    _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _onOutput('[err] $line'));

    if (!await _waitForHealth()) {
      _onOutput('[error] Server failed to become healthy.');
      _process?.kill();
      _process = null;
      return;
    }

    _onStatusChange(true);
    _onOutput(_startedMessage);

    _process!.exitCode.then((code) async {
      _process = null;
      if (await checkZonaiServerHealth()) {
        _attach();
        return;
      }
      _onOutput('Server exited (code $code).');
      _onStatusChange(false);
    });
  }

  void stop() {
    final p = _process;
    if (p != null) {
      _onOutput(_stoppedMessage);
      p.kill();
      _process = null;
      _onStatusChange(false);
      return;
    }

    if (_attached) {
      _attached = false;
      _onStatusChange(false);
      _onOutput(_stoppedMessage);
      return;
    }

    _onOutput('Server is not running.');
  }

  void dispose() {
    _process?.kill();
    _process = null;
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
