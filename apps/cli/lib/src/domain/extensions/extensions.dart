import 'dart:async' show StreamSubscription;

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/keyboard_input.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/extensions/extension_generator.dart';

/// Utilities to handle extensions to the database
class Extensions {
  factory Extensions() => _instance ??= Extensions._();
  Extensions._();
  static Extensions? _instance;

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.extensionsPath);

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

  String get executablePath => fs.path.join(settings.compiledExtensionsPath);

  Future<void> compile() async {
    if (!await _canCompile()) return;

    final directory = fs.directory(settings.extensionsPath);
    final files = directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => fs.path.extension(file.path) == '.dart')
        .toList();

    if (files.isEmpty) {
      logger.info(
        'No Dart extension files under ${directory.path}; skipping compile.',
      );
      return;
    }

    final target = fs.path.join(settings.compiledExtensionsPath);
    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await ExtensionGenerator(extensions: files).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      ExtensionGenerator.executablePath,
      '-o',
      target,
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile ${ExtensionGenerator.executablePath}');
      logger.info('----');
      logger.error('${result.stderr}');
      return;
    }

    logger.info('Compiled ${files.length} extensions');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(settings.extensionsPath);
    if (!directory.existsSync()) {
      logger.error('Extensions directory does not exist: ${directory.path}');
      return false;
    }

    // analyze directory for compile errors
    final result = await process.run('dart', ['analyze', directory.path]);
    final exitCode = await result.exitCode;

    if (exitCode != 0) {
      logger.error('Failed to compile extensions:\n${result.stderr}');
      return false;
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
