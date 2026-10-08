import 'dart:io';

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/domain/stale_workers.dart';
import 'package:zonai_logger/zonai_logger.dart';

import '../../support/temp_directory.dart';

/// `zonai serve` used to start straight from whatever was in
/// `.zonai/executables/`. The watchers only see edits made while it runs, so
/// a rule changed while the server was down kept being enforced in its old
/// form -- `canDelete` changed to `true`, a fresh `zonai serve --release`
/// still answered "Access denied: action delete" until `zonai compile`
/// (reported against v0.10.1).
void main() {
  late Directory root;
  late List<String> logs;
  late Map<String, int> compiles;

  final now = DateTime.now();
  final earlier = now.subtract(const Duration(hours: 1));
  final later = now.add(const Duration(hours: 1));

  setUp(() {
    root = createCanonicalTempSync('zonai_stale_workers_');
    logs = [];
    compiles = {};
  });

  tearDown(() => deleteTempDirectory(root));

  String path(String relative) => p.join(root.path, relative);

  void write(String relative, DateTime modified) {
    final file = File(path(relative))..createSync(recursive: true);
    file
      ..writeAsStringSync('// $relative')
      ..setLastModifiedSync(modified);
  }

  WorkerSources worker(
    String name, {
    List<String> sources = const [],
    int exitCode = 0,
  }) => WorkerSources(
    name: name,
    executablePath: path('.zonai/executables/db_$name.exe'),
    sourcePaths: [for (final source in sources) path(source)],
    compile: () async {
      compiles[name] = (compiles[name] ?? 0) + 1;
      return exitCode;
    },
  );

  T scoped<T>(T Function() body) => runScoped(
    body,
    values: {
      fsProvider.overrideWith(LocalFileSystem.new),
      loggerProvider.overrideWith(
        () => Logger(
          level: .info,
          stdout: CallbackSink(callback: (m) => logs.add('$m')),
          stderr: CallbackSink(callback: (m) => logs.add('$m')),
        ),
      ),
    },
  );

  group('findStaleWorkers', () {
    test('a source edited after the last compile makes its worker stale', () {
      write('lib/src/rules/posts.dart', later);
      write('.zonai/executables/db_rules.exe', now);

      final stale = scoped(
        () => findStaleWorkers([
          worker('rules', sources: ['lib/src/rules']),
        ]),
      );

      expect(stale.map((w) => w.name), ['rules']);
    });

    test('an executable newer than every source is fresh', () {
      write('lib/src/rules/posts.dart', earlier);
      write('.zonai/executables/db_rules.exe', later);

      final stale = scoped(
        () => findStaleWorkers([
          worker('rules', sources: ['lib/src/rules']),
        ]),
      );

      expect(stale, isEmpty);
    });

    test('a missing executable is stale when its sources exist', () {
      write('lib/src/rules/posts.dart', earlier);

      final stale = scoped(
        () => findStaleWorkers([
          worker('rules', sources: ['lib/src/rules']),
        ]),
      );

      expect(stale.map((w) => w.name), ['rules']);
    });

    test('only the worker whose sources changed is stale', () {
      write('lib/src/rules/posts.dart', later);
      write('lib/src/config/db_config.dart', earlier);
      write('.zonai/executables/db_rules.exe', now);
      write('.zonai/executables/db_config.exe', later);

      final stale = scoped(
        () => findStaleWorkers([
          worker('rules', sources: ['lib/src/rules']),
          worker('config', sources: ['lib/src/config']),
        ]),
      );

      expect(stale.map((w) => w.name), ['rules']);
    });

    test('a shared input such as .env makes every worker that lists it '
        'stale', () {
      write('lib/src/rules/posts.dart', earlier);
      write('lib/src/config/db_config.dart', earlier);
      write('.env', later);
      write('.zonai/executables/db_rules.exe', now);
      write('.zonai/executables/db_config.exe', now);

      final stale = scoped(
        () => findStaleWorkers([
          worker('rules', sources: ['lib/src/rules', '.env']),
          worker('config', sources: ['lib/src/config', '.env']),
        ]),
      );

      expect(stale.map((w) => w.name), ['rules', 'config']);
    });

    // A `zonai build` bundle ships executables and no sources. There is
    // nothing to compare against, and refusing there would refuse every
    // production deployment of a bundle.
    test('with no sources on disk, nothing is stale', () {
      final stale = scoped(
        () => findStaleWorkers([
          worker('rules', sources: ['lib/src/rules', '.env']),
        ]),
      );

      expect(stale, isEmpty);
    });
  });

  group('ensureWorkersFresh', () {
    List<WorkerSources> oneStaleOneFresh() {
      write('lib/src/rules/posts.dart', later);
      write('lib/src/config/db_config.dart', earlier);
      write('.zonai/executables/db_rules.exe', now);
      write('.zonai/executables/db_config.exe', later);
      return [
        worker('rules', sources: ['lib/src/rules']),
        worker('config', sources: ['lib/src/config']),
      ];
    }

    test('dev compiles each stale worker once, and only those', () async {
      final workers = oneStaleOneFresh();

      final ok = await scoped(
        () => ensureWorkersFresh(workers, release: false, allowStale: false),
      );

      expect(ok, isTrue);
      expect(compiles, {'rules': 1});
    });

    test('--release refuses, naming the stale workers and the fix', () async {
      final workers = oneStaleOneFresh();

      final ok = await scoped(
        () => ensureWorkersFresh(workers, release: true, allowStale: false),
      );

      expect(ok, isFalse);
      expect(compiles, isEmpty, reason: 'release serving never compiles');
      final output = logs.join('\n');
      expect(output, contains('rules'));
      expect(output, isNot(contains('config')));
      expect(output, contains('zonai compile'));
      expect(output, contains('--allow-stale-workers'));
    });

    test('--release --allow-stale-workers serves, still naming them', () async {
      final workers = oneStaleOneFresh();

      final ok = await scoped(
        () => ensureWorkersFresh(workers, release: true, allowStale: true),
      );

      expect(ok, isTrue);
      expect(compiles, isEmpty);
      expect(logs.join('\n'), contains('rules'));
    });

    test('nothing stale: no compile, no message', () async {
      write('lib/src/rules/posts.dart', earlier);
      write('.zonai/executables/db_rules.exe', later);

      final ok = await scoped(
        () => ensureWorkersFresh(
          [
            worker('rules', sources: ['lib/src/rules']),
          ],
          release: true,
          allowStale: false,
        ),
      );

      expect(ok, isTrue);
      expect(compiles, isEmpty);
      expect(logs, isEmpty);
    });

    test(
      'a failed dev compile is reported and does not stop serving',
      () async {
        write('lib/src/rules/posts.dart', later);
        write('.zonai/executables/db_rules.exe', now);

        final ok = await scoped(
          () => ensureWorkersFresh(
            [
              worker('rules', sources: ['lib/src/rules'], exitCode: 1),
            ],
            release: false,
            allowStale: false,
          ),
        );

        expect(ok, isTrue);
        expect(compiles, {'rules': 1});
        expect(logs.join('\n'), contains('Failed to compile rules'));
      },
    );
  });
}
