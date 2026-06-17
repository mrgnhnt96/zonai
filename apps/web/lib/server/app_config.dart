import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart';
import 'package:zonai_schema/payloads.dart';

const _unconfiguredAppConfig = AppConfig(
  applicationName: 'Zonai (not configured)',
  passwordSecret: 'unconfigured',
  jwtSecret: 'unconfigured',
);

/// Loads [AppConfig.applicationName] from the Zonai config worker during SSR.
Future<AppConfig> loadAppConfig() {
  return runMergedScopedFuture(
    () async {
      try {
        return await zonaiDB.getConfig();
      } on ExecutableUnavailableException {
        return _unconfiguredAppConfig;
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
