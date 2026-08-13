import 'package:zonai_schema/zonai_schema.dart';

final class DeleteOldRateLimitsCron extends CronJob {
  DeleteOldRateLimitsCron()
    : super(
        name: '_delete_old_rate_limits',
        schedule: Schedule.parse('*/15 * * * *'),
      );

  /// Longer than any reasonable app rate-limit window.
  static const maxWindowAge = Duration(days: 7);

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(maxWindowAge);

    final removed = await mutate.purge(
      tableName: '_rate_limit',
      where: Lt('window_start', cutoff),
    );

    logger.info(
      'Deleted $removed rate limits with window_start before $cutoff',
    );
  }
}

DeleteOldRateLimitsCron main() => DeleteOldRateLimitsCron();
