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

    unawaited(
      run(name: 'auto').then((_) {
        if (_rerunPending) {
          _rerunPending = false;
          _runAutoNow();
        }
      }),
    );
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
          final exitCode = await CliRunner().run(
            generateArgs(name: name, dryRun: dryRun ?? false),
          );

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
    }
  }

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
