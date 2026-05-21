import 'dart:async';

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';

import '../../deps/clean_up.dart';
import '../../deps/executable_stop.dart';
import '../../deps/fs.dart';
import '../../deps/keyboard_input.dart';
import '../../deps/logger.dart';
import '../../deps/process.dart';
import '../../deps/settings.dart';
import 'config_generator.dart';

class Config {
  Config();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.configPath);

  StreamSubscription<WatchEvent>? __subscription;

  String get executablePath => fs.path.join(settings.compiledConfigPath);

  void watch() {
    if (__subscription != null) return;

    __subscription = _watcher.events.listen((event) {
      logger.debug('Config changed: ${event.path}');
      logger.info('Detected changes in config, recompiling...');
      compile();
    });

    cleanUp.add(stop);
  }

  void stop() {
    __subscription?.cancel();
    __subscription = null;
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(settings.configPath);
    if (!directory.existsSync()) {
      logger.error('Config directory does not exist: ${directory.path}');
      return false;
    }

    final files = directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => fs.path.extension(file.path) == '.dart')
        .toList();

    if (files.isEmpty) {
      logger.info(
        'No Dart config files under ${directory.path}; skipping compile.',
      );
      return false;
    }

    return true;
  }

  Future<void> compile() async {
    if (!await _canCompile()) return;

    executableStop.request(executablePath);

    final directory = fs.directory(settings.configPath);

    final files = directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => fs.path.extension(file.path) == '.dart')
        .toList();

    if (files.isEmpty) {
      logger.info(
        'No Dart config files under ${directory.path}; skipping compile.',
      );
      return;
    }

    final target = fs.path.join(settings.compiledConfigPath);
    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await ConfigGenerator(configs: files).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      ConfigGenerator.executablePath,
      '-o',
      target,
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile ${ConfigGenerator.executablePath}');
      logger.info('----');
      logger.error('${result.stderr}');
      return;
    }

    logger.info('Compiled ${files.length} config');
  }

  void listenForKeyboardInput() {
    keyboardInput.addListener((event) {
      if (event.matches('g')) {
        logger.info('Compiling config...');
        compile();
      }
    });
  }
}
