import 'dart:async';
import 'dart:io';

import 'package:watcher/watcher.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/fs.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/domain/settings.dart';

// TODO: Create snapshot of rules so that we don't need to compile
// every file every time

class Rules {
  Rules();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(Settings.load().rulesPath);

  StreamSubscription<WatchEvent>? __subscription;

  void watch() {
    if (__subscription != null) return;

    __subscription = _watcher.events.listen((event) {
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

    final directory = fs.directory(settings.rulesPath);

    final files = directory
        .listSync(recursive: true)
        .whereType<File>()
        .toList();

    if (files.isEmpty) return;

    final processes = <(String, Future<ProcessResult>)>[];
    for (final file in files) {
      final process = Process.run('dart', [
        'compile',
        'exe',
        file.path,
        '-o',
        fs.path.join(
          settings.compiledRulesPath,
          '${fs.path.basenameWithoutExtension(file.path)}.exe',
        ),
      ]);

      processes.add((fs.path.basename(file.path), process));
    }

    final results = await Future.wait(
      processes.map((process) async {
        final (name, future) = process;
        final result = await future;
        return (name, result);
      }),
    );

    final errors = results.where((result) => result.$2.exitCode != 0).toList();
    if (errors.isNotEmpty) {
      logger.error('Failed to compile ${errors.length} rules');
      for (final (file, result) in errors) {
        logger.info('--------------------------------');
        logger.error('Failed to compile $file');
        logger.info('----');
        logger.error('${result.stderr}');
      }
      return;
    }

    logger.info('Compiled ${files.length} rules');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(Settings.load().rulesPath);
    if (!directory.existsSync()) return false;

    // analyze directory for compile errors
    final result = await Process.run('dart', ['analyze', directory.path]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile rules:\n${result.stderr}');
    }

    return true;
  }
}
