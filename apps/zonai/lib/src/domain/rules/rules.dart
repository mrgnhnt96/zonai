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
import 'rule_generator.dart';

class Rules {
  Rules();

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

    executableStop.request(executablePath);

    final directory = fs.directory(settings.rulesPath);

    final files = directory.existsSync()
        ? directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => fs.path.extension(file.path) == '.dart')
              .toList()
        : <File>[];

    if (files.isEmpty) {
      logger.info(
        'No project rule files; compiling built-in internal table rules.',
      );
    }

    final target = fs.path.join(settings.compiledRulesPath);
    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await RuleGenerator(rules: files).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      env.dartDefines,
      if (!kIsCompiled) '--enable-asserts',
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
            ? 'Failed to compile rules (dart analyze exited with $exitCode).'
            : 'Failed to compile rules:\n$details',
      );
      return false;
    }

    return true;
  }
}
