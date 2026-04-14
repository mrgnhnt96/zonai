import 'dart:async';

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/fs.dart';
import 'package:zonai_cli/src/deps/keyboard_input.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/deps/process.dart';
import 'package:zonai_cli/src/domain/rules/rule_generator.dart';
import 'package:zonai_cli/src/domain/settings.dart';

class Rules {
  factory Rules() => _instance;
  Rules._();
  static Rules get _instance => Rules._();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(Settings.load().rulesPath);

  StreamSubscription<WatchEvent>? __subscription;

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

    final settings = Settings.load();

    final directory = fs.directory(settings.rulesPath);

    final files = directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => fs.path.extension(file.path) == '.dart')
        .toList();

    if (files.isEmpty) return;

    final target = fs.path.join(settings.compiledRulesPath);
    if (!fs.directory(target).existsSync()) {
      fs.directory(target).createSync(recursive: true);
    }

    await RuleGenerator(rules: files).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      fs.path.join('.dart_tool', 'zonai', 'db_rules.dart'),
      '-o',
      fs.path.join(target, 'db_rules.exe'),
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile db_rules.exe');
      logger.info('----');
      logger.error('${result.stderr}');
      return;
    }

    logger.info('Compiled ${files.length} rules');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(Settings.load().rulesPath);
    if (!directory.existsSync()) {
      logger.error('Rules directory does not exist: ${directory.path}');
      return false;
    }

    // analyze directory for compile errors
    final result = await process.run('dart', ['analyze', directory.path]);
    final exitCode = result.exitCode;

    if (exitCode != 0) {
      logger.error('Failed to compile rules:\n${result.stderr}');
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
