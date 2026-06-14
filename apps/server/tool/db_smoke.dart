import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart';

Future<void> main() async {
  await runMergedScoped(
    () async {
      final config = await zonaiDB.getConfig();
      print('Config OK: ${config.baseUrl}');
      await zonaiDB.dispose();
    },
    includeIfAbsent: {
      argsProvider,
      cleanUpProvider,
      configProvider,
      extensionsProvider,
      executableStopProvider,
      fsProvider,
      loggerProvider,
      migrateProvider,
      mutationsProvider,
      operationsProvider,
      processProvider,
      rateLimiterProvider,
      rateLimitsProvider,
      rulesProvider,
      zonaiDbProvider,
      settingsProvider.overrideWith(() => Settings.load('../playground')),
    },
  );
}
