import 'dart:async';
import 'dart:io' as io;

import 'package:http/http.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/fs.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/deps/process.dart';
import 'package:zonai_cli/src/domain/constants.dart';

class Revali {
  factory Revali() => _instance ??= Revali._();
  Revali._();
  static Revali? _instance;

  io.Process? _process;
  bool get isRunning => _process != null;

  Future<bool> start() async {
    if (isRunning) {
      logger.err('Revali is already running');
      return true;
    }

    logger.debug('Starting Revali server');

    if (kIsCompiled) {
      logger.err(
        'Cannot start Revali in compiled mode, we haven\'t set this up yet!',
      );
      return false;
    }

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
      ['run', 'revali', 'dev'],
      workingDirectory: revaliProjectPath,
      mode: .detachedWithStdio,
    );
    final pid = result.pid;
    bool wasKilled = false;
    cleanUp.add(() {
      if (wasKilled) {
        logger.debug('Revali (server) was already killed');
        return;
      }

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
      _process = result;
      return true;
    } catch (e) {
      wasKilled = true;
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
