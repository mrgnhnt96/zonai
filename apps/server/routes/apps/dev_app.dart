import 'package:revali_router/revali_router.dart';
import 'package:zonai_server/config/server_binding.dart';
import 'package:zonai_server/setup/setup.dart';
import 'package:zonai_server/src/handlers/db_handler.dart';
import 'package:zonai_server/utils/injector.dart';
import 'package:zonai_server/utils/logger.dart' show Logger;

import '../components/log_observer.dart';

@Observers([LogObserver])
@AllowOrigins.all()
@App(flavor: 'dev')
final class DevApp extends AppConfig {
  DevApp()
    : super(host: ServerBinding.host, port: ServerBinding.port, prefix: '');

  @override
  DI initializeDI() => Injector();

  @override
  Future<void> configureDependencies(Injector di) async {
    di.registerLazySingleton(Logger.new);
    di.registerLazySingleton(DbHandler.new);
    setup(di);
  }
}
