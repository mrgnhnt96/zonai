import 'dart:async' show StreamSubscription;

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
import 'extension_generator.dart';

/// Utilities to handle extensions to the database
class Extensions {
  Extensions();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.extensionsPath);

  StreamSubscription<WatchEvent>? __subscription;

  void watch() {
    if (args.release) return;
    if (__subscription != null) return;
    fs.ensureDirectory(settings.extensionsPath);

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

  /// Compiles the extensions worker, returning `0` on success.
  ///
  /// A non-zero result is the exit code of whichever `dart` invocation failed,
  /// so `zonai compile` can propagate it (see commands/compile.dart).
  Future<int> compile({BuildSettings? buildSettings}) async {
    if (await _analyze() case final exitCode when exitCode != 0) {
      return exitCode;
    }

    executableStop.request(settings.compiledExtensionsPath);

    final directory = fs.directory(settings.extensionsPath);
    final files = directory.existsSync()
        ? directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => fs.path.extension(file.path) == '.dart')
              .toList()
        : <File>[];

    final target = switch (buildSettings) {
      != null => settings.buildExtensionsPath,
      _ => settings.compiledExtensionsPath,
    };

    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await ExtensionGenerator(extensions: files).create();

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
      ExtensionGenerator.executablePath,
      '-o',
      target,
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile ${ExtensionGenerator.executablePath}');
      logger.info('----');
      logger.error('${result.stderr}');
      return result.exitCode;
    }

    writeProtocolStamp(target);
    writeMessageContractStamp(target);

    final s = files.length == 1 ? '' : 's';
    logger.info('Compiled ${files.length} extension$s');

    return 0;
  }

  /// The exit code of `dart analyze` over the extensions sources.
  ///
  /// `0` when there is nothing to analyze, so an absent directory reads as a
  /// clean run rather than a failure.
  Future<int> _analyze() async {
    final directory = fs.directory(settings.extensionsPath);
    if (!directory.existsSync()) {
      return 0;
    }

    // analyze directory for compile errors
    final result = await process.runDart(['analyze', directory.path]);
    final exitCode = await result.exitCode;

    if (exitCode != 0) {
      final details = [
        result.stdout,
        result.stderr,
      ].map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n');
      logger.error(
        details.isEmpty
            ? 'Failed to compile extensions (dart analyze exited with $exitCode).'
            : 'Failed to compile extensions:\n$details',
      );
      return result.exitCode;
    }

    return 0;
  }
}
