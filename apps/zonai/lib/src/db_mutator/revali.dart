import 'dart:async';
import 'dart:io' as io;

import 'package:http/http.dart';
import '../../deps.dart';
import '../../gen/server/.revali/server/server.dart' as server;
import '../domain/constants.dart';

class Revali {
  factory Revali() => _instance ??= Revali._();
  Revali._();
  static Revali? _instance;

  io.Process? _process;
  bool get isRunning => switch (kIsCompiled) {
    true => _isRunning,
    false => _process != null,
  };

  /// Whether the server is running in compiled mode
  bool _isRunning = false;

  Future<bool> start() async {
    if (isRunning) {
      logger.err('Revali is already running');
      return true;
    }

    logger.debug('Starting Revali server');

    if (kIsCompiled) {
      return await _startCompiled();
    }

    return await _startDebug();
  }

  Future<bool> _startCompiled() async {
    () async {
      await runZoned(
        () async {
          await server.createServer(null, []);
        },
        zoneSpecification: .new(
          print: (_, _, _, message) {
            logger.debug(message);
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
      logger.err('Revali project path does not exist: $revaliProjectPath');
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
        logger.err('Failed to kill Revali (server)');
        logger.debug('Revali PID: $pid');
      }
    });

    if (await _checkHealth()) {
      _process = result;
      return true;
    }

    return false;
  }

  Future<bool> _checkHealth() async {
    final completer = Completer<void>();

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
      logger.err('Unexpectedly failed to make connection to Revali (server)');
      return false;
    }

    logger.debug('Revali (server) is ready!');

    try {
      await completer.future;
      return true;
    } catch (e) {
      logger.err('Error starting server');
      logger.err('$e');
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
