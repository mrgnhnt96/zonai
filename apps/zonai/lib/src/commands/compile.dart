import '../../deps.dart';

Future<int> compile() async {
  logger.info('Compiling all workers...');

  await Future.wait([
    operations.compile(),
    extensions.compile(),
    rules.compile(),
    config.compile(),
  ]);
  return 0;
}
