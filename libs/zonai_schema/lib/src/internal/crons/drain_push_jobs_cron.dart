import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Advances every unfinished push fan-out.
///
/// This is the **resume** path, not the normal one. Enqueuing a job kicks a
/// drain on the host immediately, so a notification does not wait for the
/// next minute boundary. What this cron exists for is the case that kick
/// cannot cover: a job whose drain died mid-fan-out, or one enqueued by a
/// process that has since restarted. Without it, a crash at 3am leaves a
/// half-sent fan-out sitting at its cursor until someone sends something
/// else.
///
/// `strict: false` for the same reason photo cleanup is: a missed firing is
/// caught by the next one, and there is nothing to make up.
final class DrainPushJobsCron extends CronJob {
  DrainPushJobsCron()
    : super(
        name: '_drain_push_jobs',
        schedule: Schedule.parse('* * * * *'),
        strict: false,
      );

  @override
  Future<void> run() async {
    // Non-fatal, and deliberately so: `zonai_schema` and the CLI release on
    // their own cadences, so a project can be running a newer schema than the
    // zonai binary driving it. A host that has never heard of this path
    // answers with an error response, and failing the job every minute over
    // it would bury the log in noise about a feature the deployment does not
    // have yet. Compare `_cleanup_logs`, which learned the same lesson.
    final DrainPushJobsResponse result;
    try {
      result = await msg.request<DrainPushJobsResponse>(DrainPushJobsRequest());
    } catch (e) {
      logger.warn(
        'Could not drain push jobs: $e. If this persists, the zonai binary '
        'serving this project may predate push support.',
      );
      return;
    }

    if (result.skipped case final reason?) {
      logger.warn('Did not drain push jobs: $reason');
      return;
    }

    // Silence on an empty queue. This runs every minute, and a line per
    // firing would be 1,440 a day saying nothing happened -- which is how the
    // one line that matters gets missed.
    if (result.jobsAdvanced == 0) return;

    logger.info(
      'Advanced ${result.jobsAdvanced} push job(s) '
      '(${result.jobsCompleted} completed): ${result.sent} sent, '
      '${result.permanentlyRejected} permanently rejected, '
      '${result.transientlyFailed} transiently failed',
    );
  }
}

DrainPushJobsCron main() => DrainPushJobsCron();
