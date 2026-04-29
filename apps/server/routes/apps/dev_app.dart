import 'dart:io' show HttpServer;

import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/utils/args.dart' as zonai;
import 'package:zonai/zonai.dart' hide Args;
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_server/config/server_binding.dart';
import 'package:zonai_server/src/handlers/db_handler.dart';

import '../components/log_observer.dart';

@Observers([LogObserver])
@AllowOrigins.all()
@App(flavor: 'dev')
final class DevApp extends AppConfig {
  DevApp({required this.args})
    : super(host: ServerBinding.host, port: ServerBinding.port, prefix: '');

  final Args args;

  @override
  Future<void> configureDependencies(DI di) async {
    di.registerFactory(DbHandler.new);
  }

  @override
  Future<HttpServer> runStartup(Future<HttpServer> Function() startup) async {
    return await runScoped(
      startup,
      values: {
        argsProvider.overrideWith(() => zonai.Args(args: args.values)),
        loggerProvider.overrideWith(() => Logger.print(level: .debug)),
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
