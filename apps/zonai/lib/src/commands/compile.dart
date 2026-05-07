import '../../deps.dart';

Future<int> compile() async {
  logger.info('Compiling all workers...');

  await Future.wait([
    operations.compile(),
    extensions.compile(),
    rules.compile(),
  ]);
  return 0;
}
