import 'package:zonai_schema/zonai_schema.dart';

final class CleanupCronEntriesCron extends CronJob {
  CleanupCronEntriesCron()
    : super(
        name: '_cleanup_cron_entries',
        schedule: Schedule.parse('30 3 * * *'),
      );

  static const retention = Duration(days: 30);

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(retention);

    mutate.delete.many(
      tableName: '_cron_jobs',
      updates: [],
      where: And([
        Lt('started', cutoff),
        Or([const NotNull('completed'), const NotNull('failed')]),
      ]),
    );

    logger.info('Queued deletion of cron history older than $cutoff');
  }
}

CleanupCronEntriesCron main() => CleanupCronEntriesCron();
