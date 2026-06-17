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
import 'cron_generator.dart';

final class CronsCompiler {
  CronsCompiler();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.cronsPath);

  StreamSubscription<WatchEvent>? __subscription;

  void watch() {
    if (args.release) return;

    if (__subscription != null) return;
    if (!fs.directory(settings.cronsPath).existsSync()) return;

    __subscription = _watcher.events.listen((event) {
      logger.debug('Crons changed: ${event.path}');
      logger.info('Detected changes in crons, recompiling...');
      compile();
    });

    cleanUp.add(stop);
  }

  void stop() {
    __subscription?.cancel();
    __subscription = null;
  }

  Future<void> compile({BuildSettings? buildSettings}) async {
    if (!await _canCompile()) return;

    executableStop.request(settings.compiledCronsPath);

    final directory = fs.directory(settings.cronsPath);
    final files = directory.existsSync()
        ? directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => fs.path.extension(file.path) == '.dart')
              .toList()
        : <File>[];

    final target = switch (buildSettings) {
      != null => settings.buildCronsPath,
      _ => settings.compiledCronsPath,
    };

    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await CronGenerator(crons: files).create();

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
      CronGenerator.executablePath,
      '-o',
      target,
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile ${CronGenerator.executablePath}');
      logger.error('${result.stderr}');
      return;
    }

    final s = files.length == 1 ? '' : 's';
    logger.info('Compiled ${files.length} cron$s');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(settings.cronsPath);
    if (!directory.existsSync()) {
      return true;
    }

    final result = await process.run('dart', ['analyze', directory.path]);
    if (result.exitCode != 0) {
      final details = [
        result.stdout,
        result.stderr,
      ].map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n');
      logger.error(
        details.isEmpty
            ? 'Failed to analyze crons (exit ${result.exitCode}).'
            : 'Failed to analyze crons:\n$details',
      );
      return false;
    }

    return true;
  }
}
