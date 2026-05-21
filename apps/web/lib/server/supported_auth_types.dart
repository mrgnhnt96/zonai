import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart';
import 'package:zonai_schema/payloads.dart';

/// Loads supported [AuthType] values from Zonai operations during SSR.
Future<List<AuthType>> loadSupportedAuthTypes() {
  return runMergedScopedFuture(
    () async {
      try {
        return await zonaiDB.adminSupportedAuthTypes();
      } catch (e) {
        print(e);
        return const [];
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
