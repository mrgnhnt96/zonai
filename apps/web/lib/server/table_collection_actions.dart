import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart';
import 'package:zonai_schema/payloads.dart';

/// Loads table-level collection actions from Zonai rules during SSR.
Future<Map<String, TableCollectionActions>> loadTableCollectionActions({String? authToken}) {
  return runMergedScopedFuture(
    () async {
      try {
        if (authToken == null || authToken.isEmpty) {
          return const {};
        }

        final jwt = await zonaiDB.parseJwt(authToken);

        return await zonaiDB.collectionActions(jwt: jwt);
      } on ExecutableUnavailableException {
        return const {};
      } on StateError {
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
