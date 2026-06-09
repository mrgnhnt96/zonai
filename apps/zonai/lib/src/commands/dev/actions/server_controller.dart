import 'dart:async';

import 'package:zonai/src/deps/revali.dart';

import '../../../deps/logger.dart';
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

  void _debug(String message) => logger.debug(message);

  Future<void> probe() async {
    if (isRunning) return;
    _debug('Probing for existing server...');
    final stopwatch = Stopwatch()..start();
    if (await checkZonaiServerHealth()) {
      _debug('Found existing server (${stopwatch.elapsedMilliseconds}ms)');
      _attach(quiet: true);
    } else {
      _debug('No existing server (${stopwatch.elapsedMilliseconds}ms)');
    }
  }

  Future<void> start() async {
    _debug('Starting server action...');
    final total = Stopwatch()..start();

    if (isRunning) {
      _onOutput('Server is already running.');
      return;
    }

    if (!kIsCompiled) {
      _debug('Checking for existing server health...');
      final healthCheck = Stopwatch()..start();
      if (await _waitForHealth()) {
        _debug('Server already healthy (${healthCheck.elapsedMilliseconds}ms)');
        _attach();
        _debug('Server start complete (${total.elapsedMilliseconds}ms total)');
        return;
      }
      _debug('No healthy server found (${healthCheck.elapsedMilliseconds}ms)');

      _onOutput('No server found at ${serverHealthUrl()}.');
      _onOutput(
        'Start the dev server externally (e.g. sip r play serve), then try again.',
      );
      return;
    }

    _debug('Starting compiled server...');
    _debug('Installing resqlite native library...');
    final nativeInstall = Stopwatch()..start();
    await ensureResqliteNativeInstalled();
    _debug('Resqlite native ready (${nativeInstall.elapsedMilliseconds}ms)');

    _debug('Starting revali server...');
    final revaliStart = Stopwatch()..start();
    final started = await revali.start(
      onStopped: () {
        _onOutput('Server stopped.');
        _onStatusChange(false);
      },
    );
    _debug(
      'Revali start finished: success=$started '
      '(${revaliStart.elapsedMilliseconds}ms)',
    );

    if (!started) {
      _onOutput('[error] Server failed to start.');
      return;
    }

    _onStatusChange(true);
    _onOutput(_startedMessage);
    _debug('Server start complete (${total.elapsedMilliseconds}ms total)');
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
      if (await checkZonaiServerHealth()) {
        if (i > 0) {
          _debug('Health check succeeded on attempt $i');
        }
        return true;
      }
      if (i == 0 || i % 10 == 0) {
        _debug('Health check attempt $i (no response yet)...');
      }
      if (i < attempts - 1) {
        await Future.delayed(delay);
      }
    }
    _debug('Health check gave up after $attempts attempts');
    return false;
  }
}
