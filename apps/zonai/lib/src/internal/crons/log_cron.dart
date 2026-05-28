import 'package:zonai_schema/zonai_schema.dart';

LogCron main() => LogCron();

final class LogCron extends CronJob {
  // every 5 seconds
  LogCron() : super(name: 'log', schedule: .parse('*/5 * * * * *'));

  @override
  Future<void> run() async {
    logger.info('LogCron running');
  }
}
