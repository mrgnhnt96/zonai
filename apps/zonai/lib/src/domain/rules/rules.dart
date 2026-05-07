import 'dart:async';

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';
import '../../deps/clean_up.dart';
import '../../deps/fs.dart';
import '../../deps/keyboard_input.dart';
import '../../deps/logger.dart';
import '../../deps/process.dart';
import '../../deps/settings.dart';
import 'rule_generator.dart';

class Rules {
  factory Rules() => _instance ??= Rules._();
  static Rules? _instance;
  Rules._();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.rulesPath);

  StreamSubscription<WatchEvent>? __subscription;

  String get executablePath => fs.path.join(settings.compiledRulesPath);

  void watch() {
    if (__subscription != null) return;

    __subscription = _watcher.events.listen((event) {
      logger.debug('Rules changed: ${event.path}');
      logger.info('Detected changes in rules, recompiling...');
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

    final directory = fs.directory(settings.rulesPath);

    final files = directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => fs.path.extension(file.path) == '.dart')
        .toList();

    if (files.isEmpty) {
      logger.info(
        'No Dart rule files under ${directory.path}; skipping compile.',
      );
      return;
    }

    final target = fs.path.join(settings.compiledRulesPath);
    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await RuleGenerator(rules: files).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      RuleGenerator.executablePath,
      '-o',
      target,
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile ${RuleGenerator.executablePath}');
      logger.info('----');
      logger.error('${result.stderr}');
      return;
    }

    logger.info('Compiled ${files.length} rules');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(settings.rulesPath);
    if (!directory.existsSync()) {
      logger.error('Rules directory does not exist: ${directory.path}');
      return false;
    }

    // analyze directory for compile errors
    final result = await process.run('dart', ['analyze', directory.path]);
    final exitCode = result.exitCode;

    if (exitCode != 0) {
      logger.error('Failed to compile rules:\n${result.stderr}');
      return false;
    }

    return true;
  }

  void listenForKeyboardInput() {
    keyboardInput.addListener((event) {
      if (event.matches('r')) {
        logger.info('Compiling rules...');
        compile();
      }
    });
  }
}
