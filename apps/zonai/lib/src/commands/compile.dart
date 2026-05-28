import 'package:zonai/src/domain/settings.dart';

import '../../deps.dart';

Future<int> compile([BuildSettings? settings]) async {
  logger.info('Compiling all workers...');

  await Future.wait([
    operations.compile(buildSettings: settings),
    extensions.compile(buildSettings: settings),
    rules.compile(buildSettings: settings),
    rateLimitsCompiler.compile(buildSettings: settings),
    cronsCompiler.compile(buildSettings: settings),
    config.compile(buildSettings: settings),
  ]);

  return 0;
}
