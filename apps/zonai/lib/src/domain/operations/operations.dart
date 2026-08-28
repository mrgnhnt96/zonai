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
import '../project/project_generator.dart';
import 'operation_generator.dart';

class Operations {
  Operations();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.operationsPath);

  DirectoryWatcher? __schemasWatcher;
  DirectoryWatcher get _schemasWatcher =>
      __schemasWatcher ??= DirectoryWatcher(settings.schemasPath);

  StreamSubscription<WatchEvent>? __subscription;
  StreamSubscription<WatchEvent>? __schemaSubscription;

  void watch() {
    if (args.release) return;

    fs.ensureDirectory(settings.operationsPath);
    fs.ensureDirectory(settings.schemasPath);

    var subscribed = false;

    if (__subscription == null) {
      __subscription = _watcher.events.listen((event) {
        logger.debug('Operations changed: ${event.path}');
        logger.info('Detected changes in operations, recompiling...');
        compile();
      });
      subscribed = true;
    }

    if (__schemaSubscription == null) {
      __schemaSubscription = _schemasWatcher.events.listen((event) {
        logger.debug('Schema changed: ${event.path}');
        logger.info('Detected changes in schemas, recompiling operations...');
        compile();
      });
      subscribed = true;
    }

    if (subscribed) {
      cleanUp.add(stop);
    }
  }

  void stop() {
    __subscription?.cancel();
    __subscription = null;
    __schemaSubscription?.cancel();
    __schemaSubscription = null;
  }

  /// Compiles the operations worker, returning `0` on success.
  ///
  /// A non-zero result is the exit code of whichever `dart` invocation failed,
  /// so `zonai compile` can propagate it (see commands/compile.dart).
  Future<int> compile({BuildSettings? buildSettings}) async {
    if (await _analyze() case final exitCode when exitCode != 0) {
      return exitCode;
    }

    executableStop.request(settings.compiledOperationsPath);

    final directory = fs.directory(settings.operationsPath);
    final files = directory.existsSync()
        ? directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => fs.path.extension(file.path) == '.dart')
              .toList()
        : <File>[];

    final target = switch (buildSettings) {
      != null => settings.buildOperationsPath,
      _ => settings.compiledOperationsPath,
    };
    if (fs.file(target).parent case final dir when !dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await OperationGenerator(
      operations: files,
      schemasPath: settings.schemasPath,
    ).create();
    // Keep project_main imports in sync for in-process / JIT restarts.
    await const ProjectGenerator().create();

    // One list for both compiles below -- see the note in rules.dart for why
    // they must not be spelled out separately.
    final compileArgs = [
      ...env.dartDefineArgs,
      if (!args.release) '--enable-asserts',
      ...?buildSettings?.compileTargetArgs,
    ];

    final result = await process.runDart([
      'compile',
      'exe',
      ...compileArgs,
      OperationGenerator.executablePath,
      '-o',
      target,
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile ${OperationGenerator.executablePath}');
      logger.info('----');
      logger.error('${result.stderr}');
      return result.exitCode;
    }

    writeProtocolStamp(target);
    writeMessageContractStamp(target);

    final snapshotTarget = switch (buildSettings) {
      != null => settings.buildOperationsSnapshotPath,
      _ => settings.compiledOperationsSnapshotPath,
    };
    final snapshot = await process.runDart([
      'compile',
      'aot-snapshot',
      ...compileArgs,
      OperationGenerator.executablePath,
      '-o',
      snapshotTarget,
    ]);
    if (snapshot.exitCode == 0) {
      // Its own stamp, not the .exe's: this is a separate compile of the same
      // sources, and when it fails the previous snapshot stays on disk. The
      // stamp has to describe the file that is actually there.
      writeMessageContractStamp(snapshotTarget);
    } else {
      // Deliberately a warning, and deliberately NOT part of this method's
      // exit code: the snapshot is only the fast path for the isolate
      // transport, and its absence makes the runtime fall back to spawning
      // the .exe that was just compiled above. The worker still runs, so
      // failing `zonai compile` here would refuse a build that works.
      logger.warn(
        'Failed to compile operations AOT snapshot (isolate transport '
        'will fall back to process): ${snapshot.stderr}',
      );
    }

    final s = files.length == 1 ? '' : 's';
    logger.info('Compiled ${files.length} operation$s');

    return 0;
  }

  /// The exit code of `dart analyze` over the operation sources.
  ///
  /// `0` when there is nothing to analyze, so an absent directory reads as a
  /// clean run rather than a failure.
  Future<int> _analyze() async {
    final directory = fs.directory(settings.operationsPath);
    if (!directory.existsSync()) {
      return 0;
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
            ? 'Failed to compile operations (dart analyze exited with $exitCode).'
            : 'Failed to compile operations:\n$details',
      );
      return exitCode;
    }

    return 0;
  }
}
