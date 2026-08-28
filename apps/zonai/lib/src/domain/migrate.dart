import 'dart:async';

import 'package:file/file.dart';
import 'package:meta/meta.dart';
import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:raindrop_cli/src/cli/cli_runner.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai/src/deps/args.dart';
import '../deps/clean_up.dart';
import '../deps/fs.dart';
import '../deps/keyboard_input.dart';
import '../deps/logger.dart';
import '../deps/settings.dart';
import '../deps/zonai_db.dart';
import '../utils/canonical_path.dart';
import '../utils/dart_sdk.dart';
import '../db_mutator/zonai_db/zonai_db.dart';
import '../../zonai.dart';

class Migrate {
  Migrate();

  static const _autoDebounceDuration = Duration(milliseconds: 300);

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.schemasPath);

  /// Seeds the memoized watcher so a test can deliver [WatchEvent]s itself.
  ///
  /// A real [DirectoryWatcher] cannot be told to stop: events for writes made
  /// seconds ago can still land, and a stray one arriving after the run under
  /// test finishes dispatches a follow-up run all by itself -- which is
  /// exactly the observation the rerun-drain tests are trying to make, so a
  /// broken drain would look fixed. Owning the event source removes that.
  @visibleForTesting
  set watcher(DirectoryWatcher value) => __watcher = value;

  StreamSubscription<WatchEvent>? __subscription;
  Timer? _debounce;
  bool _rerunPending = false;

  void auto() {
    if (args.release) return;
    if (__subscription != null) return;

    if (!fs.directory(settings.schemasPath).existsSync()) {
      return;
    }

    final hadMigrationsDir = fs.directory(settings.migrationsPath).existsSync();
    fs.ensureDirectory(settings.migrationsPath);

    if (!hadMigrationsDir) {
      run(name: 'initialize').catchError((e, stack) {
        logger.error('$e', 'Failed to initialize migrations', stack);
        return 1;
      }).ignore();
    }

    __subscription = _watcher.events.listen((event) {
      _scheduleAutoRun();
    });

    cleanUp.add(stop);
  }

  // Schema edits often touch several files in quick succession (e.g. a
  // multi-table change). Debounce so a burst of events becomes one run
  // against settled files, and if a run is already in flight when the
  // debounce fires, queue exactly one follow-up run instead of dropping the
  // later changes.
  void _scheduleAutoRun() {
    _debounce?.cancel();
    _debounce = Timer(_autoDebounceDuration, _runAutoNow);
  }

  void _runAutoNow() {
    if (_running != null) {
      _rerunPending = true;
      return;
    }

    // Nothing awaits this: the watcher callback is `void`, so an escaping
    // error would land as an unhandled async error and take the dev server
    // down with it. The rerun drain does NOT live here -- see
    // [_drainPendingRerun] for why it has to be every run's business, not
    // just this one's.
    unawaited(
      run(name: 'auto').catchError((Object e, StackTrace stack) {
        logger.error('$e', 'Auto migration failed', stack);
        return 1;
      }),
    );
  }

  /// Dispatches the follow-up run [_runAutoNow] queued while a run held
  /// [_running], and is called from [run]'s `finally` so that EVERY run
  /// drains -- not just the `auto` ones.
  ///
  /// It used to be a `.then` on the `run(name: 'auto')` future inside
  /// [_runAutoNow], which stranded the queue permanently in the one case
  /// [auto] creates on purpose: a fresh project has no migrations directory,
  /// so [auto] starts an `initialize` run, and a schema edit landing inside
  /// that run's window (the debounce is only 300ms, the run spawns an
  /// analyzer) queued a rerun that nothing was ever going to dispatch. That
  /// second drain also skipped on failure, because `.then` without `onError`
  /// does not run.
  ///
  /// The dispatch is deferred to a microtask rather than called inline for
  /// [run]'s own early return: `if (_running case final completer?) return
  /// completer.future;` means a caller arriving before `_running` is cleared
  /// gets the future of the run that is currently finishing instead of a new
  /// run. By the time the microtask fires, [run]'s `finally` has nulled
  /// `_running` and the follow-up is a real run. [_rerunPending] is re-read
  /// there too, so a [stop] in between cancels the drain instead of reviving
  /// a watcher that was just torn down.
  void _drainPendingRerun() {
    if (!_rerunPending) return;

    scheduleMicrotask(() {
      if (!_rerunPending) return;
      _rerunPending = false;
      _runAutoNow();
    });
  }

  void listenForKeyboardInput() {
    bool _running = false;
    keyboardInput.onKey('m', () async {
      if (_running) return;
      _running = true;
      try {
        logger.info('Running auto migration...');
        await run(name: 'auto');
        await applyPending();
      } catch (e, stack) {
        logger.error('Auto migration failed: $e', e, stack);
      } finally {
        _running = false;
      }
    });
  }

  void stop() {
    _debounce?.cancel();
    _debounce = null;
    _rerunPending = false;
    __subscription?.cancel();
    __subscription = null;
  }

  Completer<int>? _running;
  Future<int> run({required String name, bool? dryRun}) async {
    if (args.release) {
      logger.warn('Cannot generate migrations in release mode');
      return 0;
    }

    if (_running case final completer?) {
      return completer.future;
    }

    if (!fs.directory(settings.schemasPath).existsSync()) {
      logger.warn('Schemas directory does not exist: ${settings.schemasPath}');
      return 0;
    }

    var result = 0;
    try {
      _running = Completer<int>();
      bool hasChanges = false;

      // Upstream raindrop_cli writes every message with `stdout.writeln`, not
      // `print` -- there are zero `print(` calls left in it. `runZoned`'s
      // `print:` hook below therefore never fires, so the old approach of
      // matching on 'Generated migration:' / 'No schema changes detected.'
      // silently reported "No changes detected" for a run that had just
      // written a migration. Ask the filesystem instead: it is the thing we
      // actually care about, and it does not depend on upstream's wording.
      //
      // The `print:` hook is kept because it costs nothing and would start
      // routing CLI output back into zonai's logger if upstream ever restores
      // `print`. Until then two things remain broken and are NOT fixed here:
      // CLI output bypasses zonai's logger entirely (it goes straight to the
      // real stdout), and `--dry-run` writes no files, so it always reports
      // "No changes detected" even when a migration would be generated.
      // Both need a decision about capturing stdout (IOOverrides) rather than
      // a wording tweak.
      final before = _migrationFileNames();

      configureRaindropDartSdk();

      result = await runZoned(
        () async {
          final argv = generateArgs(name: name, dryRun: dryRun ?? false);
          final exitCode = await (runRaindropCli ?? _invokeRaindropCli)(argv);

          return exitCode;
        },
        zoneSpecification: .new(
          print: (_, _, _, message) {
            if (message.startsWith('Warning:')) {
              logger.warn(message);
              return;
            }

            logger.debug(message);

            switch (message) {
              case 'No schema changes detected.':
                hasChanges = false;
                return;
              case final String m
                  when m.startsWith('Generated migration:') ||
                      m.startsWith('Would generate migration:') ||
                      m.startsWith('Updated snapshot:'):
                hasChanges = true;
                return;
              case final String m when m.startsWith('No tables found'):
                logger.warn(message);
                return;
            }
          },
        ),
      );

      if (result != 0) {
        logger.warn('Migration failed (exit code $result)');
        return result;
      }

      hasChanges |= !_setEquals(before, _migrationFileNames());

      switch (hasChanges) {
        case true:
          logger.info('Generated migrations');
        case false:
          logger.info('No changes detected');
      }

      return result;
    } finally {
      _running?.complete(result);
      _running = null;
      _drainPendingRerun();
    }
  }

  /// Invokes `raindrop_cli` with [argv]. The one seam in [run] that talks to
  /// something expensive and out-of-process.
  ///
  /// Overridable because the rerun drain is a question about WHEN a run
  /// finishes relative to a watcher event, and the real CLI answers that by
  /// starting an analyzer -- a window that is seconds wide on a loaded CI
  /// runner and too narrow to hit reliably on a developer's machine, which is
  /// exactly how the stranded-rerun bug reached CI green-on-laptop. A test
  /// that can hold a run open at a known point tests the queueing instead of
  /// the hardware.
  @visibleForTesting
  Future<int> Function(List<String> argv)? runRaindropCli;

  /// Whether a watcher event arrived mid-run and is waiting for the in-flight
  /// run to finish. Exposed so a test can wait for the queue to be armed
  /// before releasing the run it is racing, rather than sleeping.
  @visibleForTesting
  bool get hasQueuedRerun => _rerunPending;

  Future<int> _invokeRaindropCli(List<String> argv) => CliRunner().run(argv);

  /// The argument vector handed to `raindrop_cli` to generate [name].
  ///
  /// Extracted so the one property that cannot be checked by running this on
  /// a developer's machine can be checked at all: `--config` and `--schemas`
  /// have to be spelled the SAME way. Upstream's `SnapshotRunner.packageUri`
  /// decides which package a schema file belongs to with
  /// `p.isWithin(<package rootUri>/lib, <schema path>)`, a pure string
  /// comparison, and it derives that package root by walking up from the
  /// `--config` directory to `package_config.json`. Two spellings of one
  /// directory therefore make every schema "not inside a package's lib/".
  ///
  /// Both go through [canonicalPath] for that reason. Resolving only
  /// `--schemas` fixed macOS (`/var` vs `/private/var`) and broke Windows,
  /// where the resolve expands a GitHub runner's 8.3 `C:\Users\RUNNER~1\...`
  /// into `C:\Users\runneradmin\...` while `--config` stayed short — the same
  /// bug the resolve was added to fix, in the other direction, on the host
  /// that had never run the suite.
  @visibleForTesting
  List<String> generateArgs({required String name, required bool dryRun}) => [
    // zonai fully drives dialect/schemas/out itself, so point --config at a
    // path that can't exist. Otherwise raindrop_cli defaults to
    // './raindrop.yaml' and would pick up an unrelated one sitting in the
    // working directory (this monorepo's own apps/zonai/raindrop.yaml, for
    // example), silently redirecting generated Dart output to wherever that
    // file's "dart:" points.
    '--config',
    canonicalPath(
      fs.path.join(settings.migrationsPath, '.raindrop-config-disabled.yaml'),
    ),
    '--driver',
    'zonai_schema',
    // Not the `raindrop_sqlite.dart` barrel: that exports
    // sqlite_delegate.dart, which needs package:sqlite3. The introspection
    // entrypoint runs inside the *user's* project, which has zonai_schema but
    // deliberately not sqlite3 (issue #24), so the barrel fails to spawn
    // there. The entrypoint only ever reads the driver's top-level `dialect`,
    // and sqlite_dialect.dart provides it with no sqlite3 in its import graph.
    '--driver-import',
    'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_dialect.dart',
    '--schema-package-prefix',
    'package:zonai_schema/gen/raindrop/raindrop/',
    '--schemas',
    canonicalPath(settings.schemasPath),
    '--out',
    settings.migrationsPath,
    'generate',
    if (dryRun) '--dry-run',
    '--name',
    name,
  ];

  /// The `*.sql` files currently in [settings.migrationsPath], by name.
  ///
  /// Empty when the directory does not exist yet, which is the first-run case.
  Set<String> _migrationFileNames() {
    final dir = fs.directory(settings.migrationsPath);
    if (!dir.existsSync()) return const {};
    return {
      for (final entity in dir.listSync())
        if (entity is File &&
            fs.path.extension(entity.path).toLowerCase() == '.sql')
          fs.path.basename(entity.path),
    };
  }

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  /// Applies pending `*.sql` files in [settings.migrationsPath] to the open DB.
  Future<int> applyPending() async {
    if (args.release) {
      logger.warn('Cannot apply migrations in release mode');
      return 0;
    }

    try {
      await zonaiDB.dispose();
      await zonaiDB.open();
      logger.info('Applied pending SQL migrations');
      return 0;
    } catch (e, stack) {
      logger.error('Failed to apply pending migrations: $e', e, stack);
      return 1;
    }
  }

  Future<List<Migration>> migrations() async {
    final migrationsDir = fs.directory(settings.migrationsPath);
    if (!migrationsDir.existsSync()) {
      if (kIsCompiled) {
        return [];
      }

      throw StateError(
        'Migrations directory does not exist: ${migrationsDir.path}\nRun `zonai db migrate generate` or `zonai serve` to setup your migrations.',
      );
    }

    final sqlFiles = <File>[];
    for (final entity in migrationsDir.listSync()) {
      if (entity is! File) continue;
      if (!fs.path.extension(entity.path).toLowerCase().endsWith('.sql')) {
        continue;
      }
      sqlFiles.add(entity);
    }

    sqlFiles.sort(
      (a, b) => fs.path.basename(a.path).compareTo(fs.path.basename(b.path)),
    );

    final migrations = <Migration>[];
    for (final file in sqlFiles) {
      final name = fs.path.basenameWithoutExtension(file.path);
      final sql = (await file.readAsString()).trim();
      migrations.add(Migration(name, sql));
    }

    return migrations;
  }
}
