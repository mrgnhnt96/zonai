import 'dart:async' show StreamSubscription;
import 'dart:io';

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/fs.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/deps/process.dart';
import 'package:zonai_cli/src/domain/settings.dart';

// TODO: Create snapshot of extensions so that we don't need to compile
// every extension every time

/// Utilities to handle extensions to the database
class Extensions {
  Extensions();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(Settings.load().extensionsPath);

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

    final directory = fs.directory(settings.extensionsPath);
    final files = directory
        .listSync(recursive: true)
        .whereType<File>()
        .toList();

    if (files.isEmpty) return;

    final processes = <(String, Future<Process>)>[];
    for (final file in files) {
      final fileName = fs.path.basename(file.path);
      if (fs.path.extension(fileName) != '.dart') continue;

      final future = process.spawn('dart', [
        'compile',
        'exe',
        file.path,
        '-o',
        fs.path.join(
          settings.compiledExtensionsPath,
          '${fs.path.basenameWithoutExtension(fileName)}.exe',
        ),
      ]);

      processes.add((fileName, future));
    }

    final results = await Future.wait(
      processes.map((process) async {
        final (name, future) = process;
        final result = await future;
        final exitCode = await result.exitCode;
        return (name, (process: result, exitCode: exitCode));
      }),
    );

    final errors = results.where((result) => result.$2.exitCode != 0).toList();
    if (errors.isNotEmpty) {
      logger.error('Failed to compile ${errors.length} extensions');
      for (final (file, result) in errors) {
        logger.info('--------------------------------');
        logger.error('Failed to compile $file');
        logger.info('----');
        logger.error('${result.process.stderr}');
      }
      return;
    }
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(Settings.load().extensionsPath);
    if (!directory.existsSync()) return false;

    // analyze directory for compile errors
    final result = await process.spawn('dart', ['analyze', directory.path]);
    final exitCode = await result.exitCode;

    if (exitCode != 0) {
      logger.error('Failed to compile extensions:\n${result.stderr}');
    }

    return true;
  }
}
