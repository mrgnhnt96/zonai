import 'package:zonai_schema/zonai_schema.dart';

final class CleanupLogsCron extends CronJob {
  CleanupLogsCron()
    : super(name: '_cleanup_logs', schedule: Schedule.parse('0 3 * * *'));

  static const retention = Duration(days: 30);

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(retention);

    mutate.delete.many(tableName: '_log', where: Lt('timestamp', cutoff));

    logger.info('Queued deletion of logs older than $cutoff');
  }
}

CleanupLogsCron main() => CleanupLogsCron();
