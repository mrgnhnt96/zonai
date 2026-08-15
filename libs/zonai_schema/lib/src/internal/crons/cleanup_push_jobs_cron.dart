import 'package:zonai_schema/zonai_schema.dart';

/// Retention for `_push_jobs`.
///
/// The table grows by one row per send and nothing else ever removes from it,
/// so without this it is a `_log` waiting to happen — that table reached
/// 4,164,727 rows in the field while its nightly cron reported success.
///
/// `mutate.purge`, not `mutate.delete`, and that is the lesson `_log` already
/// paid for: `delete` SELECTs every row it is about to remove, materialises
/// them all and dispatches a per-row rules check. Correct for author tables,
/// an OOM for retention.
final class CleanupPushJobsCron extends CronJob {
  CleanupPushJobsCron()
    : super(name: '_cleanup_push_jobs', schedule: Schedule.parse('0 4 * * *'));

  /// How long a finished job stays queryable.
  ///
  /// Longer than `_cleanup_logs`' four days on purpose: the reason to look at
  /// a job row is a complaint that a notification did or did not arrive, and
  /// those reach a developer days after the send rather than hours.
  static const retention = Duration(days: 7);

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(retention);

    // Finished jobs only, and the status filter is not an optimisation: a
    // `running` job's row *is* its cursor. Purging one by age would restart
    // its fan-out from the top on the next drain, re-notifying everyone it
    // had already reached — retention silently causing the exact duplicate
    // the checkpoint exists to prevent.
    final removed = await mutate.purge(
      tableName: '_push_jobs',
      where: And([
        Lt('updated_at', cutoff),
        In('status', const ['completed', 'failed']),
      ]),
    );

    logger.info('Deleted $removed finished push job(s) older than $cutoff');
  }
}

CleanupPushJobsCron main() => CleanupPushJobsCron();
