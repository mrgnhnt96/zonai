import 'dart:async';

import 'package:watcher/watcher.dart';

import '../../../deps/args.dart';
import '../../../deps/config.dart';
import '../../../deps/crons.dart';
import '../../../deps/extensions.dart';
import '../../../deps/fs.dart';
import '../../../deps/operations.dart';
import '../../../deps/rate_limits.dart';
import '../../../deps/rules.dart';
import '../../../deps/settings.dart';
import 'dev_action_tracker.dart';

typedef WorkerCompileFn = Future<void> Function();

/// Watches worker source directories and recompiles on change.
class WorkerWatchController {
  WorkerWatchController({
    required DevActionTracker tracker,
    required void Function(String line) onOutput,
    this.onSchemasChanged,
  }) : _tracker = tracker,
       _onOutput = onOutput;

  final DevActionTracker _tracker;
  final void Function(String line) _onOutput;
  final void Function()? onSchemasChanged;

  final _subscriptions = <StreamSubscription<WatchEvent>>[];
  final _compileChains = <String, Future<void>>{};

  static const _workerLabels = {
    'operations': 'Operations',
    'rules': 'Rules',
    'extensions': 'Extensions',
    'rate_limits': 'Rate limits',
    'crons': 'Crons',
    'config': 'Config',
  };

  void start() {
    if (args.release) return;

    _watchPath(settings.operationsPath, 'operations', operations.compile);
    _watchPath(settings.schemasPath, 'operations', () async {
      onSchemasChanged?.call();
      await operations.compile();
    });
    _watchPath(settings.rulesPath, 'rules', rules.compile);
    _watchPath(settings.extensionsPath, 'extensions', extensions.compile);
    _watchPath(
      settings.rateLimitPath,
      'rate_limits',
      rateLimitsCompiler.compile,
    );
    _watchPath(settings.cronsPath, 'crons', cronsCompiler.compile);
    _watchPath(settings.configPath, 'config', config.compile);
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _compileChains.clear();
  }

  Future<void> compileAll({bool showSuccess = true}) async {
    _onOutput('--- Compiling all workers ---');
    await Future.wait([
      _runCompile('operations', operations.compile, showSuccess: showSuccess),
      _runCompile('rules', rules.compile, showSuccess: showSuccess),
      _runCompile('extensions', extensions.compile, showSuccess: showSuccess),
      _runCompile(
        'rate_limits',
        rateLimitsCompiler.compile,
        showSuccess: showSuccess,
      ),
      _runCompile('crons', cronsCompiler.compile, showSuccess: showSuccess),
      _runCompile('config', config.compile, showSuccess: showSuccess),
    ]);
  }

  void _watchPath(String path, String workerKey, WorkerCompileFn compile) {
    final directory = fs.directory(path);
    if (!directory.existsSync()) return;

    final watcher = DirectoryWatcher(path);
    _subscriptions.add(
      watcher.events.listen((event) {
        _onOutput('Detected change: ${event.path}');
        _scheduleCompile(workerKey, compile);
      }),
    );
  }

  void _scheduleCompile(String workerKey, WorkerCompileFn compile) {
    final previous = _compileChains[workerKey] ?? Future<void>.value();
    _compileChains[workerKey] = previous.then(
      (_) => _runCompile(workerKey, compile, showSuccess: false),
    );
  }

  Future<void> _runCompile(
    String workerKey,
    WorkerCompileFn compile, {
    required bool showSuccess,
  }) {
    final label = _workerLabels[workerKey] ?? workerKey;
    return _tracker.run(label, compile, showSuccess: showSuccess);
  }
}
