import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai/gen/version.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/domain/migrate.dart';
import 'package:zonai/src/domain/settings.dart';
import 'package:zonai/src/utils/args.dart';

import '../../support/temp_directory.dart';

/// Regression test for the auto-migration rerun that was queued and never
/// dispatched.
///
/// `Migrate.auto` queues exactly one follow-up run when a watcher event
/// arrives while a run is already in flight (`_rerunPending`). Draining that
/// queue used to be a `.then` hung on the `run(name: 'auto')` future, which
/// left two ways to strand it forever:
///
///  1. `auto()` starts a `run(name: 'initialize')` of its own when the
///     migrations directory does not exist yet. That run holds `_running` and
///     has no drain, so an edit landing inside its window queued a rerun that
///     nothing would ever dispatch. The debounce is 300ms and the run spawns
///     an analyzer, so the window is wide on a first start.
///  2. `.then` without `onError` does not run when the future fails, so a
///     failing `auto` run stranded the queue too -- and raised an unhandled
///     async error on the way out, because nothing awaits that future.
///
/// Case 1 is what turned CI red on run 33144904283, on both ubuntu and
/// windows, with `migrate_auto_watch_test.dart` reporting NEITHER table of a
/// close-together two-file edit. That test drives the real `raindrop_cli`, so
/// whether it catches this is a race against how long a cold analyzer takes
/// to start: it passes in ~16s on a developer's machine and failed the whole
/// 90s budget on a loaded runner. These tests own both the clock and the
/// event source instead, so the window is not a matter of hardware.
void main() {
  group('Migrate rerun drain', () {
    late Directory projectRoot;
    late Directory schemasDir;
    late Directory migrationsDir;
    late StreamController<WatchEvent> events;
    late _GatedRaindropCli cli;
    late Migrate migrate;

    setUp(() {
      projectRoot = createCanonicalTempSync('zonai_migrate_rerun_drain_');
      schemasDir = Directory(p.join(projectRoot.path, 'lib', 'src', 'schemas'))
        ..createSync(recursive: true);
      migrationsDir = Directory(
        p.join(projectRoot.path, '.zonai', 'migrations'),
      );
      File(p.join(schemasDir.path, 'users.dart')).writeAsStringSync('// users');

      events = StreamController<WatchEvent>.broadcast();
      cli = _GatedRaindropCli();
      migrate = Migrate()
        ..runRaindropCli = cli.call
        ..watcher = _ScriptedWatcher(schemasDir.path, events.stream);
    });

    tearDown(() async {
      migrate.stop();
      cli.finishAll();
      await events.close();
      deleteTempDirectory(projectRoot);
    });

    test('drains a rerun queued behind the initialize run', () async {
      await _inScope(schemasDir, migrationsDir, () async {
        // No migrations directory yet, so `auto()` kicks off `initialize`.
        // `run()` reaches the CLI seam with no `await` in front of it, so the
        // dispatch has already happened by the time `auto()` returns.
        expect(migrationsDir.existsSync(), isFalse);
        migrate.auto();
        expect(cli.dispatched, ['initialize']);

        // A schema edit lands while `initialize` still holds `_running`.
        events.add(WatchEvent(ChangeType.ADD, _schema(schemasDir, 'posts')));
        await _waitUntil(
          () => migrate.hasQueuedRerun,
          reason: 'the debounced watcher event to queue a rerun',
        );

        // Nothing new was dispatched -- the edit is sitting in the queue, so
        // the only thing that can dispatch it is `initialize` finishing.
        expect(cli.dispatched, ['initialize']);

        cli.finish(0);

        await _waitUntil(
          () => cli.dispatched.length > 1,
          reason:
              'the queued rerun to be dispatched once the initialize run '
              'finished (this is the bug: before the fix, no run is ever '
              'dispatched for that edit)',
        );
        expect(cli.dispatched, ['initialize', 'auto']);
        expect(migrate.hasQueuedRerun, isFalse);
      });
    });

    test('drains a rerun queued behind an auto run that FAILS', () async {
      // Nothing here may await outside the guarded zone, so the body reports
      // completion through a completer: the point of the zone is to catch the
      // unhandled async error the unawaited `run(name: 'auto')` future used
      // to raise when it failed.
      final unhandled = <Object>[];
      final finished = Completer<void>();

      runZonedGuarded(() async {
        try {
          await _inScope(schemasDir, migrationsDir, () async {
            // Migrations directory already present, so no initialize run.
            migrationsDir.createSync(recursive: true);
            migrate.auto();
            expect(cli.dispatched, isEmpty);

            events.add(
              WatchEvent(ChangeType.ADD, _schema(schemasDir, 'posts')),
            );
            await _waitUntil(
              () => cli.dispatched.isNotEmpty,
              reason: 'the first auto run to be dispatched',
            );
            expect(cli.dispatched, ['auto']);

            events.add(
              WatchEvent(ChangeType.ADD, _schema(schemasDir, 'comments')),
            );
            await _waitUntil(
              () => migrate.hasQueuedRerun,
              reason: 'the second edit to queue a rerun',
            );

            cli.fail(0, StateError('raindrop_cli blew up'));

            await _waitUntil(
              () => cli.dispatched.length > 1,
              reason:
                  'the queued rerun to be dispatched even though the run '
                  'it was queued behind failed',
            );
            expect(cli.dispatched, ['auto', 'auto']);
          });
          finished.complete();
        } catch (error, stackTrace) {
          finished.completeError(error, stackTrace);
        }
      }, (error, _) => unhandled.add(error));

      await finished.future;
      // A `.then` with no `onError` left the failure with nowhere to go, and
      // nothing awaits this future -- in the dev server that is an unhandled
      // async error, not a logged one.
      expect(unhandled, isEmpty);
    });
  });
}

/// Runs [body] with the dependencies [Migrate] reads, pointed at the fixture.
///
/// Everything that touches a provider has to be inside: the watcher
/// subscription, the debounce timer and the run it dispatches all inherit the
/// zone that `auto()` was called in.
Future<void> _inScope(
  Directory schemasDir,
  Directory migrationsDir,
  Future<void> Function() body,
) => runScoped(
  body,
  values: {
    settingsProvider.overrideWith(
      () => _fixtureSettings(schemasDir.path, migrationsDir.path),
    ),
    argsProvider.overrideWith(() => const Args()),
    fsProvider,
    loggerProvider,
    cleanUpProvider,
  },
);

Settings _fixtureSettings(String schemasPath, String migrationsPath) =>
    Settings(
      path: 'zonai.yml',
      migrationsPath: migrationsPath,
      dataPath: '.zonai/data',
      schemasPath: schemasPath,
      extensionsPath: '.zonai/unused/extensions',
      rulesPath: '.zonai/unused/rules',
      operationsPath: '.zonai/unused/operations',
      configPath: '.zonai/unused/config',
      emailTemplatesPath: '.zonai/unused/email_templates',
      rateLimitPath: '.zonai/unused/rate_limit',
      cronsPath: '.zonai/unused/crons',
      imagesPath: '.zonai/unused/images',
      buildSettings: BuildSettings.current(),
      version: kVersion,
    );

String _schema(Directory schemasDir, String name) =>
    p.join(schemasDir.path, '$name.dart');

/// Stands in for `raindrop_cli`, recording each dispatch and holding the run
/// open until the test says otherwise.
class _GatedRaindropCli {
  /// The `--name` of every run dispatched, in order.
  final dispatched = <String>[];
  final _gates = <Completer<int>>[];

  Future<int> call(List<String> argv) {
    dispatched.add(argv[argv.indexOf('--name') + 1]);
    final gate = Completer<int>();
    _gates.add(gate);
    return gate.future;
  }

  /// Finishes the [index]th dispatched run successfully.
  void finish(int index, {int exitCode = 0}) =>
      _gates[index].complete(exitCode);

  /// Finishes the [index]th dispatched run by throwing.
  void fail(int index, Object error) => _gates[index].completeError(error);

  void finishAll() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete(0);
    }
  }
}

/// A [DirectoryWatcher] whose events the test writes by hand.
class _ScriptedWatcher implements DirectoryWatcher {
  _ScriptedWatcher(this.path, this.events);

  @override
  final String path;

  @override
  final Stream<WatchEvent> events;

  @override
  String get directory => path;

  @override
  bool get isReady => true;

  @override
  Future<void> get ready async {}
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 10),
}) async {
  // Seconds, not minutes: nothing here spawns a process or starts an
  // analyzer, so anything slower than this is wedged rather than busy.
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for: $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
