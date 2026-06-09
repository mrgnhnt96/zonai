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

  Future<bool> start({void Function()? onStopped}) async {
    final isDev = args['dev'] == true;
    void devLog(String message) {
      if (isDev) logger.debug(message);
    }

    if (isRunning) {
      logger.debug('Revali is already running');
      return true;
    }

    // during development, the server could already be running, so we can just return true
    if (!(isDev && kIsCompiled)) {
      devLog('Quick health check...');
      final quickHealth = Stopwatch()..start();
      if (await _checkHealth(quick: true)) {
        logger.debug('Revali server is already running');
        devLog(
          'Quick health check passed (${quickHealth.elapsedMilliseconds}ms)',
        );
        _isRunning = true;
        return true;
      }
      devLog(
        'Quick health check failed (${quickHealth.elapsedMilliseconds}ms)',
      );
    } else {
      devLog('Skipping quick health check (starting compiled server)');
    }

    logger.debug('Starting Revali server');
    devLog('Launching revali server process...');

    if (kIsCompiled) {
      return await _startCompiled(onStopped: onStopped);
    }

    return await _startDebug(isDev: isDev);
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

  Future<bool> _startCompiled({void Function()? onStopped}) async {
    final isDev = args['dev'] == true;
    void devLog(String message) {
      if (isDev) logger.debug(message);
    }

    devLog('Acquiring serve lock...');
    final lockWatch = Stopwatch()..start();
    _serveLock = ServeLock.tryAcquire();
    if (_serveLock == null) {
      devLog('Serve lock unavailable (${lockWatch.elapsedMilliseconds}ms)');
      return false;
    }
    devLog('Serve lock acquired (${lockWatch.elapsedMilliseconds}ms)');

    final cliLogger = logger;

    devLog('Creating HTTP server...');
    final createServerWatch = Stopwatch()..start();
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
        devLog(
          'HTTP server created (${createServerWatch.elapsedMilliseconds}ms)',
        );
      } catch (e, stack) {
        _isRunning = false;
        logger.error('Server exited unexpectedly', e, stack);
        devLog(
          'HTTP server creation failed (${createServerWatch.elapsedMilliseconds}ms)',
        );
        if (!isDev) {
          logger.debug('Killing process');
          kill.force();
        }
        onStopped?.call();
        await stop();
      }
    }());

    devLog('Waiting for server health...');
    final healthWatch = Stopwatch()..start();
    if (await _checkHealth(devLog: isDev)) {
      devLog('Server healthy (${healthWatch.elapsedMilliseconds}ms)');
      _isRunning = true;
      return true;
    }

    devLog('Server health check failed (${healthWatch.elapsedMilliseconds}ms)');
    await stop();
    return false;
  }

  Future<bool> _startDebug({required bool isDev}) async {
    void devLog(String message) {
      if (isDev) logger.debug(message);
    }

    logger.debug('Current dir: ${fs.currentDirectory.path}');
    final revaliProjectPath = fs.path.normalize(
      fs.path.join(fs.currentDirectory.path, '..', 'server'),
    );
    logger.debug('revaliProjectPath: $revaliProjectPath');
    devLog('Revali project path: $revaliProjectPath');

    if (!fs.directory(revaliProjectPath).existsSync()) {
      logger.error('Revali project path does not exist: $revaliProjectPath');
      devLog('Revali project path does not exist');
      return false;
    }

    devLog('Spawning revali dev subprocess...');
    final spawnWatch = Stopwatch()..start();
    final result = await process.start(
      'dart',
      ['run', 'revali', 'dev', '--loud'],
      workingDirectory: revaliProjectPath,
      mode: .detachedWithStdio,
    );
    devLog(
      'Subprocess spawned (pid=${result.pid}, ${spawnWatch.elapsedMilliseconds}ms)',
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

    devLog('Waiting for server health...');
    final healthWatch = Stopwatch()..start();
    if (await _checkHealth(devLog: isDev)) {
      devLog('Server healthy (${healthWatch.elapsedMilliseconds}ms)');
      _process = result;
      return true;
    }

    devLog('Server health check failed (${healthWatch.elapsedMilliseconds}ms)');
    return false;
  }

  Future<bool> _checkHealth({bool quick = false, bool devLog = false}) async {
    if (quick) {
      return await health();
    }

    bool isReady = false;
    var attempts = 0;
    const maxAttempts = 200;
    while (!isReady && attempts < maxAttempts) {
      logger.debug('Checking health of Revali (server) - Attempt $attempts');
      if (devLog && (attempts == 0 || attempts % 10 == 0)) {
        logger.debug('Health check attempt $attempts...');
      }
      isReady = await health();
      attempts++;

      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!isReady) {
      logger.error('Unexpectedly failed to make connection to Revali (server)');
      if (devLog) {
        logger.debug('Health check gave up after $attempts attempts');
      }
      return false;
    }

    logger.debug('Revali (server) is ready!');
    if (devLog) {
      logger.debug('Health check passed after $attempts attempts');
    }

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
