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

  /// Compiles the rules worker, returning `0` on success.
  ///
  /// A non-zero result is the exit code of whichever `dart` invocation failed,
  /// so `zonai compile` can propagate it (see commands/compile.dart).
  Future<int> compile({BuildSettings? buildSettings}) async {
    if (await _analyze() case final exitCode when exitCode != 0) {
      return exitCode;
    }

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

    // One list for both compiles below. They emit the same code for the same
    // target and differ only in output format, so a flag either belongs to both
    // or to neither -- and the one time they were spelled out separately, the
    // snapshot silently came out for the build host.
    final compileArgs = [
      ...env.dartDefineArgs,
      if (!args.release) '--enable-asserts',
      ...?buildSettings?.compileTargetArgs,
    ];

    final result = await process.runDart([
      'compile',
      'exe',
      ...compileArgs,
      RuleGenerator.executablePath,
      '-o',
      target,
    ]);

    if (result.exitCode != 0) {
      logger.error('Failed to compile ${RuleGenerator.executablePath}');
      logger.info('----');
      logger.error('${result.stderr}');
      return result.exitCode;
    }

    writeProtocolStamp(target);
    writeMessageContractStamp(target);

    final snapshotTarget = switch (buildSettings) {
      != null => settings.buildRulesSnapshotPath,
      _ => settings.compiledRulesSnapshotPath,
    };
    // A cross-target bundle must not carry a snapshot. `dart compile
    // aot-snapshot` takes no --target-os -- unlike the .exe above, which
    // `compileArgs` aims -- so emitting one here puts a BUILD-HOST snapshot
    // beside a TARGET binary. settings.dart's `compileTargetArgs` already
    // records that `zonai build` shipped exactly that for two releases.
    //
    // It used to fail softly: the spawn was refused and mailman fell back to
    // the .exe worker, which is what tool/ci/verify_cross_target_bundle.sh
    // asserts by grepping for the "would not spawn" warning. That stopped
    // being true the day CI moved to Dart 3.13.2 -- once two SDKs differ by a
    // snapshot CONTAINER format the process takes SIGABRT inside
    // snapshot_utils.cc before any Dart code runs, and there is nothing to
    // catch. A bundle whose downloaded host binary predates the `.sdk` guard
    // cannot refuse it either, which is why not emitting it is the fix rather
    // than relying on the guard to decline it.
    //
    // Costs in-process dispatch on cross-built bundles and nothing else: with
    // no snapshot present mailman serves through the .exe worker, the same
    // answer by a different transport. A leftover from an earlier
    // same-platform build is DELETED, not merely left unwritten -- shipping
    // the leftover is the whole bug.
    final crossTarget =
        buildSettings != null && !buildSettings.targetsCurrentPlatform();
    if (crossTarget) {
      for (final stale in [
        snapshotTarget,
        messageContractStampPathFor(snapshotTarget),
        snapshotSdkStampPathFor(snapshotTarget),
      ]) {
        if (fs.file(stale).existsSync()) fs.file(stale).deleteSync();
      }
    }
    final snapshot = crossTarget
        ? null
        : await process.runDart([
            'compile',
            'aot-snapshot',
            ...compileArgs,
            RuleGenerator.executablePath,
            '-o',
            snapshotTarget,
          ]);
    if (snapshot == null) {
      // Nothing to stamp and nothing to warn about: the absence is
      // deliberate and the .exe beside it is the supported transport.
    } else if (snapshot.exitCode == 0) {
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
      // Deliberately a warning, and deliberately NOT part of this method's
      // exit code: the snapshot is only the fast path for the isolate
      // transport, and its absence makes the runtime fall back to spawning
      // the .exe that was just compiled above. The worker still runs, so
      // failing `zonai compile` here would refuse a build that works.
      logger.warn(
        'Failed to compile rules AOT snapshot (isolate transport '
        'will fall back to process): ${snapshot.stderr}',
      );
    }

    final s = files.length == 1 ? '' : 's';
    logger.info('Compiled ${files.length} rule$s');

    return 0;
  }

  /// The exit code of `dart analyze` over the rules sources.
  ///
  /// `0` when there is nothing to analyze, so an absent directory reads as a
  /// clean run rather than a failure.
  Future<int> _analyze() async {
    final directory = fs.directory(settings.rulesPath);
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
            ? 'Failed to compile rules (dart analyze exited with $exitCode).'
            : 'Failed to compile rules:\n$details',
      );
      return result.exitCode;
    }

    return 0;
  }
}
