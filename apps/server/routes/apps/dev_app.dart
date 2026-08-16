import 'dart:io' show HttpServer, Platform;

import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart' hide Args;
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_server/components/lifecycle_components/external_idp_provisioning.dart';
import 'package:zonai_server/components/lifecycle_components/trace_id.dart';
import 'package:zonai_server/config/server_binding.dart';
import 'package:zonai_server/src/handlers/auth_handler.dart';
import 'package:zonai_server/src/handlers/cron_handler.dart';
import 'package:zonai_server/src/handlers/dashboard_handler.dart';
import 'package:zonai_server/src/handlers/db_handler.dart';
import 'package:zonai_server/src/handlers/email_handler.dart';
import 'package:zonai_server/src/handlers/maintenance_handler.dart';
import 'package:zonai_server/src/handlers/photo_handler.dart';
import 'package:zonai_server/src/handlers/push_handler.dart';

import '../components/exception_catcher.dart';

@Exceptions()
@AllowOrigins.all()
@Trace()
@ExternalIdpProvisioning()
@App(flavor: 'dev')
final class DevApp extends AppConfig {
  DevApp()
    : super(
        host: ServerBinding.host,
        port: ServerBinding.port,
        prefix: '',
        // Multi-isolate accept only after host-side IPC caches / in-process
        // sanitize — otherwise each isolate would spawn its own Mailman pools
        // against one SQLite file. Opt in with ZONAI_HTTP_WORKERS; default 1.
        workers: _httpWorkers,
      );

  static int get _httpWorkers {
    final raw = Platform.environment['ZONAI_HTTP_WORKERS'];
    final parsed = int.tryParse(raw ?? '');
    if (parsed == null || parsed < 1) return 1;
    return parsed;
  }

  TrustedProxy _trustedProxy = const TrustedProxy();

  @override
  TrustedProxy get trustedProxy => _trustedProxy;

  @override
  Future<void> configureDependencies(DI di) async {
    di.registerFactory(DbHandler.new);
    di.registerFactory(AuthHandler.new);
    di.registerFactory(DashboardHandler.new);
    di.registerFactory(CronHandler.new);
    di.registerFactory(MaintenanceHandler.new);
    di.registerFactory(EmailHandler.new);
    di.registerFactory(PhotoHandler.new);
    di.registerFactory(PushHandler.new);
  }

  @override
  void onServerStarted(HttpServer server) {
    super.onServerStarted(server);
    print('Access the UI at http://${server.address.host}:${server.port}/_');
  }

  @override
  Future<HttpServer> runStartup(Future<HttpServer> Function() startup) async {
    final parentLogger = read(
      loggerProvider,
      orElse: () => Logger.print(level: .info),
    );

    return await runMergedScoped(
      () async {
        final config = await zonaiDB.getConfig();
        _trustedProxy = TrustedProxy(
          headers: config.trustedProxy.headers,
          useLeftmostIp: config.trustedProxy.useLeftmostIp,
        );
        return startup();
      },
      override: {loggerProvider.overrideWith(() => parentLogger)},
      includeIfAbsent: {
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
        migrateProvider,
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
