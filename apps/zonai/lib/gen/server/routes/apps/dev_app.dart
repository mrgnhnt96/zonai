import 'dart:io' show HttpServer;

import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import '../../../../deps.dart';
import '../../../../zonai.dart' hide Args;
import 'package:zonai_logger/zonai_logger.dart';
import '../../lib/config/server_binding.dart';
import '../../lib/src/handlers/db_handler.dart';

import '../components/log_observer.dart';

@Observers([LogObserver])
@AllowOrigins.all()
@App(flavor: 'dev')
final class DevApp extends AppConfig {
  DevApp()
    : super(host: ServerBinding.host, port: ServerBinding.port, prefix: '');

  @override
  Future<void> configureDependencies(DI di) async {
    di.registerFactory(DbHandler.new);
  }

  @override
  Future<HttpServer> runStartup(Future<HttpServer> Function() startup) async {
    return await runMergedScoped(
      startup,
      includeIfAbsent: {
        loggerProvider.overrideWith(() => Logger.print(level: .debug)),
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
}
