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
import '../project/project_generator.dart';
import 'rule_generator.dart';

class Rules {
  Rules();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.rulesPath);

  StreamSubscription<WatchEvent>? __subscription;

  void watch() {
    if (args.release) return;

    if (__subscription != null) return;
    fs.ensureDirectory(settings.rulesPath);

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

  Future<void> compile({BuildSettings? buildSettings}) async {
    if (!await _canCompile()) return;

    executableStop.request(settings.compiledRulesPath);

    final directory = fs.directory(settings.rulesPath);

    final files = directory.existsSync()
        ? directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => fs.path.extension(file.path) == '.dart')
              .toList()
        : <File>[];

    if (files.isEmpty) {
      logger.warn('Nothing in rules, creating empty worker');
    }

    final target = switch (buildSettings) {
      != null => settings.buildRulesPath,
      _ => settings.compiledRulesPath,
    };
    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await RuleGenerator(rules: files).create();
    await const ProjectGenerator().create();

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

    final snapshotTarget = switch (buildSettings) {
      != null => settings.buildRulesSnapshotPath,
      _ => settings.compiledRulesSnapshotPath,
    };
    final snapshot = await process.runDart([
      'compile',
      'aot-snapshot',
      ...env.dartDefineArgs,
      if (!args.release) '--enable-asserts',
      RuleGenerator.executablePath,
      '-o',
      snapshotTarget,
    ]);
    if (snapshot.exitCode != 0) {
      logger.warn(
        'Failed to compile rules AOT snapshot (isolate transport '
        'will fall back to process): ${snapshot.stderr}',
      );
    }

    final s = files.length == 1 ? '' : 's';
    logger.info('Compiled ${files.length} rule$s');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(settings.rulesPath);
    if (!directory.existsSync()) {
      return true;
    }

    final result = await process.runDart(['analyze', directory.path]);
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
