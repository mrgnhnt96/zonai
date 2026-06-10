import 'package:zonai_schema/zonai_schema.dart';

final class DeleteExpiredJwtsCron extends CronJob {
  DeleteExpiredJwtsCron()
    : super(
        name: '_delete_expired_jwts',
        schedule: Schedule.parse('0 4 * * *'),
        strict: false,
      );

  @override
  Future<void> run() async {
    final now = DateTime.now();

    mutate.delete.many(tableName: '_jwt', where: Lt('expires_at', now));

    logger.info('Queued deletion of JWTs expired before $now');
  }
}

DeleteExpiredJwtsCron main() => DeleteExpiredJwtsCron();
