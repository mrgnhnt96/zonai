import 'dart:async';
import 'dart:io' as io;

import 'package:scoped_deps/scoped_deps.dart';
import '../../deps.dart';
import '../../gen/server/.revali/server/server.dart' as server;
import '../../gen/server/lib/config/server_binding.dart';
import '../domain/constants.dart';
import 'host_worker_registries.dart';
import '../utils/serve_lock.dart';
import '../utils/server_health.dart';

class Revali {
  Revali();

  io.Process? _process;
  io.HttpServer? _httpServer;
  ServeLock? _serveLock;

  /// In-process HTTP ([createServer]) — AOT project/bootstrap binaries, or
  /// JIT project entry with linked ops/rules registries.
  bool get _inProcessHttp => kIsCompiled || HostWorkerRegistries.hasOperations;

  bool get isRunning =>
      _isRunning ??
      switch (_inProcessHttp) {
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

    if (_inProcessHttp) {
      devLog('Acquiring serve lock...');
      final lockWatch = Stopwatch()..start();
      _serveLock = ServeLock.tryAcquire();
      devLog(
        'Serve lock ${_serveLock == null ? 'unavailable' : 'acquired'} '
        '(${lockWatch.elapsedMilliseconds}ms)',
      );
    }

    // during development, the server could already be running, so we can just return true
    if (!(isDev && _inProcessHttp)) {
      devLog('Quick health check...');
      final quickHealth = Stopwatch()..start();
      final isHealthy = await _checkHealth(quick: true);
      devLog(
        'Quick health check ${isHealthy ? 'passed' : 'failed'} '
        '(${quickHealth.elapsedMilliseconds}ms)',
      );

      if (isHealthy) {
        // We hold this project's serve lock, so no other process serving
        // *this* project could be the one answering the health check.
        // Something else owns this project's configured port -- most
        // likely another zonai project. Don't silently pretend we're
        // running.
        if (_inProcessHttp && _serveLock != null) {
          logger.error(
            'Port ${ServerBinding.port} is already in use by another '
            'process. If you have another zonai project running '
            '(`zonai serve` or `zonai dev`), stop it first -- only one '
            'zonai server can bind this port at a time.',
          );
          _releaseServeLock();
          return false;
        }

        logger.debug('Revali server is already running');
        _isRunning = true;
        return true;
      }
    } else {
      devLog('Skipping quick health check (starting compiled server)');
    }

    logger.debug('Starting Revali server');
    devLog('Launching revali server process...');

    if (_inProcessHttp) {
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

    // Acquired earlier in start(); a null lock here means another process is
    // already serving this exact project (see ServeLock.tryAcquire logging).
    if (_serveLock == null) {
      return false;
    }

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
          io.exitCode = 1;
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

  Future<bool> health() async => checkZonaiServerHealth(
    host: ServerBinding.host,
    port: ServerBinding.port,
  );

  void _releaseServeLock() {
    _serveLock?.release();
    _serveLock = null;
  }
}
