import 'package:zonai_schema/zonai_schema.dart';

final class CleanupAuthChallengesCron extends CronJob {
  CleanupAuthChallengesCron()
    : super(
        name: '_cleanup_auth_challenges',
        schedule: Schedule.parse('15 3 * * *'),
      );

  @override
  Future<void> run() async {
    final now = DateTime.now();

    mutate.delete.many(
      tableName: '_auth_challenges',
      where: Lt('expires_at', now),
    );

    logger.info('Queued deletion of auth challenges expired before $now');
  }
}

CleanupAuthChallengesCron main() => CleanupAuthChallengesCron();
