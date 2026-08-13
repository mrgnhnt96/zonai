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

    final removed = await mutate.purge(
      tableName: '_cron_jobs',
      where: And([
        Lt('started', cutoff),
        Or([const NotNull('completed'), const NotNull('failed')]),
      ]),
    );

    logger.info('Deleted $removed cron history entries older than $cutoff');
  }
}

CleanupCronEntriesCron main() => CleanupCronEntriesCron();
