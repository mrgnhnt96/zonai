import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class CleanupLogsCron extends CronJob {
  CleanupLogsCron()
    : super(name: '_cleanup_logs', schedule: Schedule.parse('0 3 * * *'));

  static const retention = Duration(days: 4);

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(retention);

    final removed = await mutate.purge(
      tableName: '_log',
      where: Lt('timestamp', cutoff),
    );

    logger.info('Deleted $removed log records older than $cutoff');

    // Deleting is only half of reclaiming. SQLite moves the emptied pages to
    // a freelist and reuses them for future writes; the file itself does not
    // shrink, so a deployment watching `df` sees retention run every night
    // and the number never move. Rewriting the file is what returns them, and
    // it is only safe to do from here now that `_log` lives in its own
    // database -- a `VACUUM` on the shared file would take its exclusive lock
    // on application data for the duration.
    //
    // The host decides whether to actually do it: the pragmas and the
    // volume's free space are both on that side. A skip is normal (usually
    // "nothing worth reclaiming") and says so.
    final space = await msg.request<ReclaimLogSpaceResponse>(
      ReclaimLogSpaceRequest(),
    );

    if (space.vacuumed) {
      logger.info(
        'Reclaimed ${space.reclaimedBytes} bytes from the log database',
      );
    } else if (space.skipped case final reason?) {
      logger.warn(
        'Did not rewrite the log database ($reason); '
        '${space.reclaimableBytes} bytes remain on its freelist',
      );
    }
  }
}

CleanupLogsCron main() => CleanupLogsCron();
