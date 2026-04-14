import 'dart:async' show StreamSubscription;

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/fs.dart';
import 'package:zonai_cli/src/deps/keyboard_input.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/deps/process.dart';
import 'package:zonai_cli/src/domain/extender_file.dart';
import 'package:zonai_cli/src/domain/settings.dart';

/// Utilities to handle extensions to the database
class Extensions {
  factory Extensions() => _instance;
  Extensions._();
  static Extensions get _instance => Extensions._();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(Settings.load().extensionsPath);

  StreamSubscription<WatchEvent>? __subscription;

  void watch() {
    if (__subscription != null) return;

    __subscription = _watcher.events.listen((event) {
      logger.debug('Extensions changed: ${event.path}');
      logger.info('Detected changes in extensions, recompiling...');
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
        .where((file) => fs.path.extension(file.path) == '.dart')
        .toList();

    if (files.isEmpty) return;

    final target = fs.path.join(settings.compiledExtensionsPath);
    if (!fs.directory(target).existsSync()) {
      fs.directory(target).createSync(recursive: true);
    }

    await ExtenderFile(extensions: files).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      fs.path.join('.dart_tool', 'zonai', 'db_extender.dart'),
      '-o',
      fs.path.join(target, 'db_extender.exe'),
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile db_extender.exe');
      logger.info('----');
      logger.error('${result.stderr}');
      return;
    }

    logger.info('Compiled ${files.length} extensions');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(Settings.load().extensionsPath);
    if (!directory.existsSync()) return false;

    // analyze directory for compile errors
    final result = await process.run('dart', ['analyze', directory.path]);
    final exitCode = await result.exitCode;

    if (exitCode != 0) {
      logger.error('Failed to compile extensions:\n${result.stderr}');
    }

    return true;
  }

  void listenForKeyboardInput() {
    keyboardInput.addListener((event) {
      if (event.matches('e')) {
        logger.info('Compiling extensions...');
        compile();
      }
    });
  }
}
