import 'dart:async';

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';
import '../../deps/clean_up.dart';
import '../../deps/fs.dart';
import '../../deps/keyboard_input.dart';
import '../../deps/logger.dart';
import '../../deps/process.dart';
import '../../deps/settings.dart';
import 'operation_generator.dart';

class Operations {
  factory Operations() => _instance ??= Operations._();
  static Operations? _instance;
  Operations._();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.operationsPath);

  StreamSubscription<WatchEvent>? __subscription;

  String get executablePath => fs.path.join(settings.compiledOperationsPath);

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
    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await OperationGenerator(operations: files).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      OperationGenerator.executablePath,
      '-o',
      target,
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile ${OperationGenerator.executablePath}');
      logger.info('----');
      logger.error('${result.stderr}');
      return;
    }

    logger.info('Compiled ${files.length} operations');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(settings.operationsPath);
    if (!directory.existsSync()) {
      logger.error('Operations directory does not exist: ${directory.path}');
      return false;
    }

    // analyze directory for compile errors
    final result = await process.run('dart', ['analyze', directory.path]);
    final exitCode = result.exitCode;

    if (exitCode != 0) {
      final details = [
        result.stdout,
        result.stderr,
      ].map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n');
      logger.error(
        details.isEmpty
            ? 'Failed to compile operations (dart analyze exited with $exitCode).'
            : 'Failed to compile operations:\n$details',
      );
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
