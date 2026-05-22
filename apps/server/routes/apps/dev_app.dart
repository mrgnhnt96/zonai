import 'dart:io' show HttpServer;

import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart' hide Args;
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_server/components/lifecycle_components/trace_id.dart';
import 'package:zonai_server/config/server_binding.dart';
import 'package:zonai_server/src/handlers/auth_handler.dart';
import 'package:zonai_server/src/handlers/db_handler.dart';
import 'package:zonai_server/src/handlers/email_handler.dart';

import '../components/exception_catcher.dart';
import '../components/log_observer.dart';

@Exceptions()
@Observers([LogObserver])
@AllowOrigins.all()
@Trace()
@App(flavor: 'dev')
final class DevApp extends AppConfig {
  DevApp()
    : super(host: ServerBinding.host, port: ServerBinding.port, prefix: '');

  @override
  Future<void> configureDependencies(DI di) async {
    di.registerFactory(DbHandler.new);
    di.registerFactory(AuthHandler.new);
    di.registerFactory(EmailHandler.new);
  }

  @override
  Future<HttpServer> runStartup(Future<HttpServer> Function() startup) async {
    return await runMergedScoped(
      startup,
      includeIfAbsent: {
        loggerProvider.overrideWith(() => Logger.print(level: .verbose)),
        argsProvider,
        courierProvider,
        envProvider,
        cleanUpProvider,
        mutationsProvider,
        zonaiDbProvider,
        extensionsProvider,
        executableStopProvider,
        rateLimiterProvider,
        rateLimitsProvider,
        rulesProvider,
        operationsProvider,
        configProvider,
        configResolverProvider,
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
