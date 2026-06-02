import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart';
import 'package:zonai_schema/payloads.dart';

/// Loads [TableSchemaShape] values from Zonai operations during SSR.
Future<Map<String, TableSchemaShape>> loadTableSchemaShapes() {
  return runMergedScopedFuture(
    () async {
      try {
        return await zonaiDB.schemaShapes();
      } on ExecutableUnavailableException {
        return const {};
      }
    },
    includeIfAbsent: {
      argsProvider,
      cleanUpProvider,
      configProvider,
      configResolverProvider,
      extensionsProvider,
      executableStopProvider,
      processProvider,
      loggerProvider,
      fsProvider,
      operationsProvider,
      rulesProvider,
      rateLimitsProvider,
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
