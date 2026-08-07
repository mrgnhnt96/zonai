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
import '../ipc_protocol_stamp.dart';
import 'config_generator.dart';

class Config {
  Config();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.configPath);

  StreamSubscription<WatchEvent>? __subscription;

  void watch() {
    if (args.release) return;
    if (__subscription != null) return;
    fs.ensureDirectory(settings.configPath);

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

  Future<void> compile({BuildSettings? buildSettings}) async {
    if (!await _canCompile()) return;

    executableStop.request(settings.compiledConfigPath);

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

    final target = switch (buildSettings) {
      != null => settings.buildConfigPath,
      _ => settings.compiledConfigPath,
    };

    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await ConfigGenerator(configs: files).create();

    final result = await process.runDart([
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

    writeProtocolStamp(target);

    final s = files.length == 1 ? '' : 's';
    logger.info('Compiled ${files.length} config$s');
  }
}
