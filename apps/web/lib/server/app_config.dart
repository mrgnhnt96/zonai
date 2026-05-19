import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart';
import 'package:zonai_schema/payloads.dart';

/// Loads [AppConfig.appName] from the Zonai config worker during SSR.
Future<AppConfig> loadAppConfig() {
  return runMergedScopedFuture(
    () async {
      try {
        return await zonaiDB.getConfig();
      } catch (e) {
        print(e);
        rethrow;
      }
    },
    includeIfAbsent: {
      argsProvider,
      cleanUpProvider,
      configProvider,
      configResolverProvider,
      extensionsProvider,
      processProvider,
      loggerProvider,
      fsProvider,
      operationsProvider,
      rulesProvider,
      settingsProvider.overrideWith(() {
        if (kIsCompiled) {
          return Settings.load();
        }
        return Settings.load(fs.path.join('..', 'playground'));
      }),
      zonaiDbProvider,
    },
  );
}
