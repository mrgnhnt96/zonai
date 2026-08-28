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
import '../message_contract_stamp.dart';
import 'rate_limit_generator.dart';

final class RateLimitsCompiler {
  RateLimitsCompiler();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.rateLimitPath);

  StreamSubscription<WatchEvent>? __subscription;

  String get executablePath => fs.path.join(settings.compiledRateLimitPath);

  void watch() {
    if (args.release) return;

    if (__subscription != null) return;
    fs.ensureDirectory(settings.rateLimitPath);

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

  /// Compiles the rate limits worker, returning `0` on success.
  ///
  /// A non-zero result is the exit code of whichever `dart` invocation failed,
  /// so `zonai compile` can propagate it (see commands/compile.dart).
  Future<int> compile({BuildSettings? buildSettings}) async {
    if (await _analyze() case final exitCode when exitCode != 0) {
      return exitCode;
    }

    executableStop.request(executablePath);

    final directory = fs.directory(settings.rateLimitPath);
    final files = directory.existsSync()
        ? directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => fs.path.extension(file.path) == '.dart')
              .toList()
        : <File>[];

    final target = switch (buildSettings) {
      != null => settings.buildRateLimitPath,
      _ => settings.compiledRateLimitPath,
    };

    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await RateLimitGenerator(rateLimits: files).create();

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
      RateLimitGenerator.executablePath,
      '-o',
      target,
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile ${RateLimitGenerator.executablePath}');
      logger.error('${result.stderr}');
      return result.exitCode;
    }

    writeProtocolStamp(target);
    writeMessageContractStamp(target);

    final s = files.length == 1 ? '' : 's';
    logger.info('Compiled ${files.length} rate limit$s');

    return 0;
  }

  /// The exit code of `dart analyze` over the rate limits sources.
  ///
  /// `0` when there is nothing to analyze, so an absent directory reads as a
  /// clean run rather than a failure.
  Future<int> _analyze() async {
    final directory = fs.directory(settings.rateLimitPath);
    if (!directory.existsSync()) {
      return 0;
    }

    final result = await process.runDart(['analyze', directory.path]);
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
      return result.exitCode;
    }

    return 0;
  }
}
