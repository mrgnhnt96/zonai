import 'dart:async' show StreamSubscription;

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/settings.dart';
import '../../deps/clean_up.dart';
import '../../deps/fs.dart';
import '../../deps/logger.dart';
import '../../deps/process.dart';
import '../../deps/executable_stop.dart';
import '../../deps/settings.dart';
import '../../deps/args.dart';
import '../../deps/env.dart';
import 'extension_generator.dart';

/// Utilities to handle extensions to the database
class Extensions {
  Extensions();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.extensionsPath);

  StreamSubscription<WatchEvent>? __subscription;

  void watch() {
    if (args['release'] case true) return;
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

  Future<void> compile({BuildSettings? buildSettings}) async {
    if (!await _canCompile()) return;

    executableStop.request(executablePath);

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

    final target = switch (buildSettings) {
      != null => settings.buildExtensionsPath,
      _ => settings.compiledExtensionsPath,
    };

    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await ExtensionGenerator(extensions: files).create();

    final result = await process.run('dart', [
      'compile',
      'exe',
      ...env.dartDefineArgs,
      if (!kReleaseMode) '--enable-asserts',
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
      return;
    }

    final s = files.length == 1 ? '' : 's';
    logger.info('Compiled ${files.length} extension$s');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(settings.extensionsPath);
    if (!directory.existsSync()) {
      return false;
    }

    // analyze directory for compile errors
    final result = await process.run('dart', ['analyze', directory.path]);
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
      return false;
    }

    return true;
  }
}
