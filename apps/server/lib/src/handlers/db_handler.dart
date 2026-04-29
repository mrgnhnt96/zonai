import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/clean_up.dart';
import 'package:zonai/src/deps/extensions.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/migrate.dart';
import 'package:zonai/src/deps/operations.dart';
import 'package:zonai/src/deps/process.dart';
import 'package:zonai/src/deps/rules.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/settings.dart';

class DbHandler {
  const DbHandler();

  void get() {}

  Future<List<Map<String, Object?>>> search() async {
    return await _runScoped(() async {
      return await zonaiDB.search('items', {});
    });
  }

  Future<List<Map<String, Object?>>> list() async {
    return await _runScoped(() async {
      return await zonaiDB.list('items', {});
    });
  }

  void create() {}

  void update() {}

  void updateMany() {}

  void delete() {}
}

// TODO: create `zoned` in revali to add the dependencies to the zone
// ! This is not optimal, since the zone needs to be recreated for each request
Future<T> _runScoped<T>(Future<T> Function() fn) async {
  return await runScoped(
    () async {
      return await fn();
    },
    values: {
      argsProvider,
      cleanUpProvider,
      zonaiDbProvider,
      extensionsProvider,
      rulesProvider,
      operationsProvider,
      migrateProvider,
      loggerProvider,
      fsProvider,
      processProvider,
      settingsProvider.overrideWith(() {
        if (kIsCompiled) {
          return Settings.load();
        }

        final settings = Settings.load(fs.path.join('..', 'playground'));
        return settings;
      }),
    },
  );
}
