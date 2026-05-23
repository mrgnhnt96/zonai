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
import 'rate_limit_generator.dart';

final class RateLimitsCompiler {
  RateLimitsCompiler();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.rateLimitPath);

  StreamSubscription<WatchEvent>? __subscription;

  String get executablePath => fs.path.join(settings.compiledRateLimitPath);

  void watch() {
    if (__subscription != null) return;

    __subscription = _watcher.events.listen((event) {
      logger.debug('Rate limits changed: ${event.path}');
      logger.info('Detected changes in rate limits, recompiling...');
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

    final directory = fs.directory(settings.rateLimitPath);
    final files = directory.existsSync()
        ? directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => fs.path.extension(file.path) == '.dart')
              .toList()
        : <File>[];

    if (files.isEmpty) {
      logger.warn('Nothing in rate limits, creating an empty worker');
    }

    final target = settings.compiledRateLimitPath;
    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await RateLimitGenerator(rateLimits: files).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      ...env.dartDefineArgs,
      if (!kReleaseMode) '--enable-asserts',
      RateLimitGenerator.executablePath,
      '-o',
      target,
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile ${RateLimitGenerator.executablePath}');
      logger.error('${result.stderr}');
      return;
    }

    final s = files.length == 1 ? '' : 's';
    logger.info('Compiled ${files.length} rate limit$s');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(settings.rateLimitPath);
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
            ? 'Failed to analyze rate limits (exit ${result.exitCode}).'
            : 'Failed to analyze rate limits:\n$details',
      );
      return false;
    }

    return true;
  }
}
