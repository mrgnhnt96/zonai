import 'dart:async';
import 'dart:io' as io;

import 'package:http/http.dart';
import 'package:scoped_deps/scoped_deps.dart';
import '../../deps.dart';
import '../../gen/server/.revali/server/server.dart' as server;
import '../domain/constants.dart';

class Revali {
  Revali();

  io.Process? _process;
  bool get isRunning =>
      _isRunning ??
      switch (kIsCompiled) {
        true => false,
        false => _process != null,
      };

  /// Whether the server is running in compiled mode
  bool? _isRunning = false;

  Future<bool> start() async {
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
      return await _startCompiled();
    }

    return await _startDebug();
  }

  Future<bool> _startCompiled() async {
    final cliLogger = logger;

    () async {
      await runMergedScopedFuture(
        () => server.createServer(null, []),
        zoneSpecification: .new(
          print: (self, parent, zone, message) {
            cliLogger.info(message);
          },
        ),
      );
    }().catchError((e, stack) {
      _isRunning = false;
      logger.error('Server exited unexpectedly', e, stack);
      logger.debug('Killing process');
      kill.force();

      return null;
    });

    if (await _checkHealth()) {
      _isRunning = true;
      return true;
    }

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

  Future<bool> health() async {
    try {
      final result = await get(Uri.parse('http://localhost:8080/health'));

      return result.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
