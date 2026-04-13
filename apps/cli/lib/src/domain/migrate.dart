import 'dart:async';

import 'package:watcher/watcher.dart';
import 'package:zonai_cli/src/deps/clean_up.dart';
import 'package:zonai_cli/src/domain/settings.dart';
import 'package:raindrop_cli/src/cli/cli_runner.dart';

class Migrate {
  Migrate();

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

  void stop() {
    __subscription?.cancel();
    __subscription = null;
  }

  Future<int> run({required String name, bool? dryRun}) async {
    final settings = Settings.load();

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
  }
}
