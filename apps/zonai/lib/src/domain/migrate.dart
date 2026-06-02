import 'dart:async';

import 'package:file/file.dart';
import 'package:raindrop/raindrop.dart';
import 'package:raindrop_cli/src/cli/cli_runner.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai/src/deps/args.dart';
import '../deps/clean_up.dart';
import '../deps/fs.dart';
import '../deps/keyboard_input.dart';
import '../deps/logger.dart';
import '../deps/settings.dart';
import '../../zonai.dart';

class Migrate {
  Migrate();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.migrationsPath);

  StreamSubscription<WatchEvent>? __subscription;

  void auto() {
    if (args.release) return;
    if (__subscription != null) return;

    if (fs.directory(settings.migrationsPath) case final dir
        when !dir.existsSync()) {
      if (!fs.directory(settings.schemasPath).existsSync()) {
        return;
      }

      run(name: 'initialize').catchError((e, stack) {
        logger.error('$e', 'Failed to initialize migrations', stack);
        return 1;
      }).ignore();
    }

    __subscription = _watcher.events.listen((event) async {
      run(name: 'auto');
    });

    cleanUp.add(stop);
  }

  void listenForKeyboardInput() {
    bool _running = false;
    keyboardInput.onKey('m', () async {
      if (_running) return;
      _running = true;
      try {
        logger.info('Running auto migration...');
        await run(name: 'auto');
      } catch (e, stack) {
        logger.error('Auto migration failed: $e', e, stack);
      } finally {
        _running = false;
      }
    });
  }

  void stop() {
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

      result = await runZoned(
        () async {
          final exitCode = await CliRunner().run([
            '--dialect',
            'sqlite',
            '--schemas',
            settings.schemasPath,
            '--out',
            settings.migrationsPath,
            'generate',
            if (dryRun case true) '--dry-run',
            '--name',
            name,
          ]);

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
