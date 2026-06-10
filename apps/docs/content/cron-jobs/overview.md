---
title: Cron Jobs Overview
description: What cron jobs are and how they run in Zonai.
---

Cron jobs are scheduled background tasks that run on a timer, independent of HTTP requests. Write them in Dart, and Zonai compiles them into the crons worker.

Use cron jobs for: purging old data, sending periodic digests, flagging stale records, running maintenance tasks.

## How Jobs Run

The cron worker runs each job on its configured `Schedule`. Jobs run one at a time — if a job is still running when its next scheduled time arrives, that run is skipped (see [Catch-Up Logic](/cron-jobs/catch-up-logic)).

Errors thrown from `run()` are caught, logged, and do not crash the server.

## The CronJwt Identity

When a cron job calls `get`, `mutate`, or `email`, it uses an internal system identity. This identity has admin-level access — it passes most authorization checks by default, but rules still execute.

## The _cron_jobs Table

Zonai records each job run in the internal `_cron_jobs` table:
- Job name, start time, end time
- Status: success or error
- Error message if the job failed

Query this table to audit job history or debug failures.

## Creating a Job

Create a file in `cronsPath` (any name), extend `CronJob`, and export a `main()` function:

```dart
import 'package:zonai_schema/zonai_schema.dart';

final class CleanupOldLogsJob extends CronJob {
  CleanupOldLogsJob()
    : super(name: 'cleanup-old-logs', schedule: Schedule.parse('0 3 * * *'));

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    mutate.delete.many(
      tableName: '_log',
      updates: [],
      where: Lt('created_at', cutoff),
    );
    logger.info('Queued deletion of logs older than $cutoff');
  }
}

CleanupOldLogsJob main() => CleanupOldLogsJob();
```

## Related

- [Defining a Job](/cron-jobs/defining-a-job)
- [Catch-Up Logic](/cron-jobs/catch-up-logic)
- [Side Effects in Cron Jobs](/cron-jobs/side-effects)
- [Running Jobs Manually](/cron-jobs/running-manually)
