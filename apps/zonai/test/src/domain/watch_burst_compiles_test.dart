import 'dart:async';
import 'dart:io';

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/config/config.dart';
import 'package:zonai/src/domain/rules/rules.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../../support/temp_directory.dart';

/// A burst of watcher events -- one per file, as a `git checkout` or a
/// formatter produces -- must not become one concurrent compile per event.
///
/// Reported against v0.10.0: after a burst touching every file under config/,
/// schemas/ and rules/, `zonai serve` in dev mode started ~20 overlapping
/// `dart compile exe` runs of the same worker, which clobbered each other's
/// `.exe` and left the rules worker broken.
///
/// The compiles here only count themselves (and take long enough to overlap
/// if anything lets them), so the test is about the scheduling, not about how
/// long a real `dart compile` takes.
void main() {
  late Directory root;
  late List<String> logs;

  setUp(() {
    logs = [];
    root = createCanonicalTempSync('zonai_watch_burst_');
    for (final dir in ['rules', 'config']) {
      Directory(p.join(root.path, dir)).createSync(recursive: true);
    }
  });

  tearDown(() => deleteTempDirectory(root));

  Future<T> scoped<T>(Future<T> Function() body) => runScoped(
    body,
    values: {
      settingsProvider.overrideWith(
        () => Settings(
          path: 'zonai.yml',
          migrationsPath: p.join(root.path, 'migrations'),
          dataPath: p.join(root.path, 'data'),
          schemasPath: p.join(root.path, 'schemas'),
          extensionsPath: p.join(root.path, 'extensions'),
          rulesPath: p.join(root.path, 'rules'),
          operationsPath: p.join(root.path, 'operations'),
          configPath: p.join(root.path, 'config'),
          emailTemplatesPath: p.join(root.path, 'email_templates'),
          rateLimitPath: p.join(root.path, 'rate_limit'),
          cronsPath: p.join(root.path, 'crons'),
          imagesPath: p.join(root.path, 'images'),
          buildSettings: BuildSettings.current(),
          version: kVersion,
        ),
      ),
      argsProvider.overrideWith(() => const Args()),
      fsProvider.overrideWith(LocalFileSystem.new),
      loggerProvider.overrideWith(
        () => Logger(
          level: .error,
          stdout: CallbackSink(callback: (m) => logs.add('$m')),
          stderr: CallbackSink(callback: (m) => logs.add('$m')),
        ),
      ),
      cleanUpProvider,
    },
  );

  /// Writes [count] files into [dir] as fast as the filesystem allows.
  void burst(String dir, int count) {
    for (var i = 0; i < count; i++) {
      File(p.join(root.path, dir, 'file_$i.dart')).writeAsStringSync('// $i');
    }
  }

  test('a burst in rules/ is one compile, never two at once', () async {
    final rules = _CountingRules();
    await scoped(() async {
      rules.watch();
      // Let the platform watcher start before the burst: events before it is
      // ready are not what this test is about.
      await Future<void>.delayed(const Duration(seconds: 1));

      burst('rules', 14);
      await Future<void>.delayed(const Duration(seconds: 3));
      rules.stop();
    });

    expect(rules.counter.peak, 1, reason: 'compiles overlapped');
    expect(
      rules.counter.calls,
      inInclusiveRange(1, 2),
      reason: 'a burst of 14 events compiled ${rules.counter.calls} times',
    );
  });

  test('a burst in config/ is one compile, never two at once', () async {
    final config = _CountingConfig();
    await scoped(() async {
      config.watch();
      await Future<void>.delayed(const Duration(seconds: 1));

      burst('config', 14);
      await Future<void>.delayed(const Duration(seconds: 3));
      config.stop();
    });

    expect(config.counter.peak, 1, reason: 'compiles overlapped');
    expect(config.counter.calls, inInclusiveRange(1, 2));
  });

  test('a change during a compile is still compiled afterwards', () async {
    final rules = _CountingRules(compileTime: const Duration(seconds: 1));
    await scoped(() async {
      rules.watch();
      await Future<void>.delayed(const Duration(seconds: 1));

      burst('rules', 3);
      // Well inside the first compile's second.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      File(p.join(root.path, 'rules', 'late.dart')).writeAsStringSync('// l');
      await Future<void>.delayed(const Duration(seconds: 4));
      rules.stop();
    });

    expect(rules.counter.peak, 1);
    expect(rules.counter.calls, 2, reason: 'the late edit was compiled too');
  });
}

final class _Counter {
  _Counter(this.compileTime);

  final Duration compileTime;
  int calls = 0;
  int _inFlight = 0;
  int peak = 0;

  Future<int> run() async {
    calls++;
    _inFlight++;
    if (_inFlight > peak) peak = _inFlight;
    try {
      await Future<void>.delayed(compileTime);
      return 0;
    } finally {
      _inFlight--;
    }
  }
}

final class _CountingRules extends Rules {
  _CountingRules({Duration compileTime = const Duration(milliseconds: 400)})
    : counter = _Counter(compileTime);

  final _Counter counter;

  @override
  Future<int> compile({BuildSettings? buildSettings}) => counter.run();
}

final class _CountingConfig extends Config {
  _CountingConfig() : counter = _Counter(const Duration(milliseconds: 400));

  final _Counter counter;

  @override
  Future<int> compile({BuildSettings? buildSettings}) => counter.run();
}
