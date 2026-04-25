import 'dart:async';

import 'package:file/file.dart';
import 'package:raindrop/raindrop.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/fs.dart';
import 'package:zonai_cli/src/deps/keyboard_input.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/deps/settings.dart';
import 'package:zonai_cli/src/domain/settings.dart';
import 'package:raindrop_cli/src/cli/cli_runner.dart';

class Migrate {
  factory Migrate() => _instance ??= Migrate._();
  Migrate._();
  static Migrate? _instance;

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(settings.migrationsPath);

  StreamSubscription<WatchEvent>? __subscription;

  void auto() {
    if (__subscription != null) return;

    __subscription = _watcher.events.listen((event) async {
      run(name: 'auto');
    });

    cleanUp.add(stop);
  }

  void listenForKeyboardInput() {
    keyboardInput.addListener((event) {
      if (event.matches('m')) {
        logger.info('Running auto migration...');
        run(name: 'auto');
      }
    });
  }

  void stop() {
    __subscription?.cancel();
    __subscription = null;
  }

  Future<int> run({required String name, bool? dryRun}) async {
    bool hasChanges = false;

    final result = await runZoned(
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
          logger.debug(message);

          switch (message) {
            case 'No schema changes detected.':
              hasChanges = false;
              return;
          }
        },
      ),
    );

    switch (hasChanges) {
      case true:
        logger.info('Generated migrations');
      case false:
        logger.info('No changes detected');
    }

    return result;
  }

  Future<List<Migration>> migrations() async {
    final migrationsDir = fs.directory(settings.migrationsPath);
    if (!migrationsDir.existsSync()) {
      throw StateError(
        'Migrations directory does not exist: ${migrationsDir.path}',
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
