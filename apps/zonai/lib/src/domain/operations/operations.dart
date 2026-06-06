import 'dart:async';

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai/src/domain/settings.dart';

import '../../deps/args.dart';
import '../../deps/clean_up.dart';
import '../../deps/env.dart';
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

  DirectoryWatcher? __schemasWatcher;
  DirectoryWatcher? get _schemasWatcher {
    final dir = fs.directory(settings.schemasPath);
    if (!dir.existsSync()) return null;
    return __schemasWatcher ??= DirectoryWatcher(settings.schemasPath);
  }

  StreamSubscription<WatchEvent>? __subscription;
  StreamSubscription<WatchEvent>? __schemaSubscription;

  void watch() {
    if (args.release) return;

    if (__subscription == null) {
      __subscription = _watcher.events.listen((event) {
        logger.debug('Operations changed: ${event.path}');
        logger.info('Detected changes in operations, recompiling...');
        compile();
      });
    }

    if (__schemaSubscription == null) {
      final schemasWatcher = _schemasWatcher;
      if (schemasWatcher != null) {
        __schemaSubscription = schemasWatcher.events.listen((event) {
          logger.debug('Schema changed: ${event.path}');
          logger.info('Detected changes in schemas, recompiling operations...');
          compile();
        });
      }
    }

    if (__subscription != null || __schemaSubscription != null) {
      cleanUp.add(stop);
    }
  }

  void stop() {
    __subscription?.cancel();
    __subscription = null;
    __schemaSubscription?.cancel();
    __schemaSubscription = null;
  }

  Future<void> compile({BuildSettings? buildSettings}) async {
    if (!await _canCompile()) return;

    executableStop.request(settings.compiledOperationsPath);

    final directory = fs.directory(settings.operationsPath);
    final files = directory.existsSync()
        ? directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => fs.path.extension(file.path) == '.dart')
              .toList()
        : <File>[];

    final target = switch (buildSettings) {
      != null => settings.buildOperationsPath,
      _ => settings.compiledOperationsPath,
    };
    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await OperationGenerator(
      operations: files,
      schemasPath: settings.schemasPath,
    ).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      ...env.dartDefineArgs,
      if (!args.release) '--enable-asserts',
      if (buildSettings case final build?) ...[
        '--target-os',
        build.targetOs.name,
        '--target-arch',
        build.targetArch.name,
      ],
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
