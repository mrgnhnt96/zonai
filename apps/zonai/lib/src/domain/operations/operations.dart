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
import '../../utils/dart_sdk.dart';
import '../ipc_protocol_stamp.dart';
import '../message_contract_stamp.dart';
import '../project/project_generator.dart';
import '../snapshot_sdk_stamp.dart';
import '../vm_snapshot_hash.dart';
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

  Future<void> compile({BuildSettings? buildSettings}) async {
    if (!await _canCompile()) return;

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
      return;
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

      // The COMPILING SDK's hash, not this process's. The two differ in
      // exactly the case the `.sdk` sidecar exists to catch -- a host built by
      // CI's pinned SDK being handed a snapshot a developer's newer SDK
      // produced -- and reading the host's would record the one number that
      // can never disagree. Resolved once and used for both the hash and the
      // version, rather than once per value.
      final dart = await resolveDartExecutable();
      writeSnapshotSdkStamp(
        snapshotTarget,
        hash: sdkVmSnapshotHash(dart),
        version: await dartSdkVersion(dart),
      );
    } else {
      logger.warn(
        'Failed to compile operations AOT snapshot (isolate transport '
        'will fall back to process): ${snapshot.stderr}',
      );
    }

    final s = files.length == 1 ? '' : 's';
    logger.info('Compiled ${files.length} operation$s');
  }

  Future<bool> _canCompile() async {
    final directory = fs.directory(settings.operationsPath);
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
            ? 'Failed to compile operations (dart analyze exited with $exitCode).'
            : 'Failed to compile operations:\n$details',
      );
      return false;
    }

    return true;
  }
}
