import 'dart:async';

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai/src/deps/env.dart';
import 'package:zonai/src/domain/constants.dart';

import '../../deps/clean_up.dart';
import '../../deps/executable_stop.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';
import '../../deps/process.dart';
import '../../deps/settings.dart';
import 'operation_generator.dart';

class Operations {
  Operations();

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

    executableStop.request(executablePath);

    final directory = fs.directory(settings.operationsPath);
    final files = directory.existsSync()
        ? directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => fs.path.extension(file.path) == '.dart')
              .toList()
        : <File>[];

    if (files.isEmpty) {
      logger.warn('Nothing in operations, creating an empty worker');
    }

    final target = fs.path.join(settings.compiledOperationsPath);
    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await OperationGenerator(operations: files).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      ...env.dartDefineArgs,
      if (!kReleaseMode) '--enable-asserts',
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

    final s = files.length == 1 ? '' : 's';
    logger.info('Compiled ${files.length} operation$s');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(settings.operationsPath);
    if (!directory.existsSync()) {
      return true;
    }

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
}
