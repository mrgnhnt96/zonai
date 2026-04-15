import 'dart:async';

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/fs.dart';
import 'package:zonai_cli/src/deps/keyboard_input.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/deps/process.dart';
import 'package:zonai_cli/src/domain/operations/operation_generator.dart';
import 'package:zonai_cli/src/domain/settings.dart';

class Operations {
  factory Operations() => _instance ??= Operations._();
  static Operations? _instance;
  Operations._();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(Settings.load().operationsPath);

  StreamSubscription<WatchEvent>? __subscription;

  void watch() {
    if (__subscription != null) return;

    __subscription = _watcher.events.listen((event) {
      logger.debug('Operations changed: ${event.path}');
      logger.info('Detected changes in operations, recompiling...');
      compile();
    });

    cleanUp.add(stop);
  }

  void stop() {
    __subscription?.cancel();
    __subscription = null;
  }

  Future<void> compile() async {
    if (!await _canCompile()) return;

    final settings = Settings.load();

    final directory = fs.directory(settings.operationsPath);
    final files = directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => fs.path.extension(file.path) == '.dart')
        .toList();

    if (files.isEmpty) {
      logger.info(
        'No Dart operation files under ${directory.path}; skipping compile.',
      );
      return;
    }

    final target = fs.path.join(settings.compiledOperationsPath);
    if (!fs.directory(target).existsSync()) {
      fs.directory(target).createSync(recursive: true);
    }

    await OperationGenerator(operations: files).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      fs.path.join('.dart_tool', 'zonai', 'db_operations.dart'),
      '-o',
      fs.path.join(target, 'db_operations.exe'),
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile db_operations.exe');
      logger.info('----');
      logger.error('${result.stderr}');
      return;
    }

    logger.info('Compiled ${files.length} operations');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(Settings.load().operationsPath);
    if (!directory.existsSync()) {
      logger.error('Operations directory does not exist: ${directory.path}');
      return false;
    }

    // analyze directory for compile errors
    final result = await process.run('dart', ['analyze', directory.path]);
    final exitCode = result.exitCode;

    if (exitCode != 0) {
      logger.error('Failed to compile operations:\n${result.stderr}');
      return false;
    }

    return true;
  }

  void listenForKeyboardInput() {
    keyboardInput.addListener((event) {
      if (event.matches('o')) {
        logger.info('Compiling operations...');
        compile();
      }
    });
  }
}
