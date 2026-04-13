import 'dart:async';

import 'package:watcher/watcher.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/deps/keyboard_input.dart';
import 'package:zonai_cli/src/deps/logger.dart';
import 'package:zonai_cli/src/domain/settings.dart';
import 'package:raindrop_cli/src/cli/cli_runner.dart';

class Migrate {
  factory Migrate() => _instance;
  Migrate._();
  static Migrate get _instance => Migrate._();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(Settings.load().migrationsPath);

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
    final settings = Settings.load();

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
}
