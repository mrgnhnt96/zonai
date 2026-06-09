import 'dart:async';
import 'dart:io' as io;

import 'package:scoped_deps/scoped_deps.dart';
import '../../deps.dart';
import '../../gen/server/.revali/server/server.dart' as server;
import '../domain/constants.dart';
import '../utils/serve_lock.dart';
import '../utils/server_health.dart';

class Revali {
  Revali();

  io.Process? _process;
  io.HttpServer? _httpServer;
  ServeLock? _serveLock;

  bool get isRunning =>
      _isRunning ??
      switch (kIsCompiled) {
        true => false,
        false => _process != null,
      };

  /// Whether the server is running in compiled mode
  bool? _isRunning = false;

  Future<bool> start({bool isDev = false, void Function()? onStopped}) async {
    if (isRunning) {
      logger.debug('Revali is already running');
      return true;
    }

    // during development, the server could already be running, so we can just return true
    if (await _checkHealth(quick: true)) {
      logger.debug('Revali server is already running');
      _isRunning = true;
      return true;
    }

    logger.debug('Starting Revali server');

    if (kIsCompiled) {
      return await _startCompiled(isDev: isDev, onStopped: onStopped);
    }

    return await _startDebug();
  }

  Future<void> stop() async {
    _isRunning = false;

    final httpServer = _httpServer;
    _httpServer = null;
    if (httpServer != null) {
      await httpServer.close(force: true);
    }

    final proc = _process;
    _process = null;
    if (proc != null) {
      proc.kill();
    }

    _releaseServeLock();
  }

  Future<bool> _startCompiled({
    required bool isDev,
    void Function()? onStopped,
  }) async {
    _serveLock = ServeLock.tryAcquire();
    if (_serveLock == null) {
      return false;
    }

    final cliLogger = logger;

    unawaited(() async {
      try {
        _httpServer = await runMergedScopedFuture(
          () => server.createServer(null, []),
          zoneSpecification: .new(
            print: (self, parent, zone, message) {
              cliLogger.info(message);
            },
          ),
        );
      } catch (e, stack) {
        _isRunning = false;
        logger.error('Server exited unexpectedly', e, stack);
        if (!isDev) {
          logger.debug('Killing process');
          kill.force();
        }
        onStopped?.call();
        await stop();
      }
    }());

    if (await _checkHealth()) {
      _isRunning = true;
      return true;
    }

    await stop();
    return false;
  }

  Future<bool> _startDebug() async {
    logger.debug('Current dir: ${fs.currentDirectory.path}');
    final revaliProjectPath = fs.path.normalize(
      fs.path.join(fs.currentDirectory.path, '..', 'server'),
    );
    logger.debug('revaliProjectPath: $revaliProjectPath');

    if (!fs.directory(revaliProjectPath).existsSync()) {
      logger.error('Revali project path does not exist: $revaliProjectPath');
      return false;
    }

    final result = await process.start(
      'dart',
      ['run', 'revali', 'dev', '--loud'],
      workingDirectory: revaliProjectPath,
      mode: .detachedWithStdio,
    );
    final pid = result.pid;
    cleanUp.add(() {
      if (result.kill()) {
        logger.debug('Killed Revali (server)');
        return;
      }

      final success = process.kill(pid);
      if (success) {
        logger.debug('Killed Revali (server)');
      } else {
        logger.error('Failed to kill Revali (server)');
        logger.debug('Revali PID: $pid');
      }
    });

    if (await _checkHealth()) {
      _process = result;
      return true;
    }

    return false;
  }

  Future<bool> _checkHealth({bool quick = false}) async {
    if (quick) {
      return await health();
    }

    bool isReady = false;
    var attempts = 0;
    const maxAttempts = 200;
    while (!isReady && attempts < maxAttempts) {
      logger.debug('Checking health of Revali (server) - Attempt $attempts');
      isReady = await health();
      attempts++;

      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!isReady) {
      logger.error('Unexpectedly failed to make connection to Revali (server)');
      return false;
    }

    logger.debug('Revali (server) is ready!');

    try {
      return true;
    } catch (e) {
      logger.error('Error starting server');
      logger.error('$e');
      return false;
    }
  }

  Future<bool> health() async => checkZonaiServerHealth();

  void _releaseServeLock() {
    _serveLock?.release();
    _serveLock = null;
  }
}
