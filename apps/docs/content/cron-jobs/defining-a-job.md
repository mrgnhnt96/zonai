---
title: Defining a Job
description: How to create and configure a cron job class.
---

## CronJob Class

Create a file in `cronsPath`, extend `CronJob`, and export a `main()` function returning the job instance:

```dart
import 'package:zonai_schema/zonai_schema.dart';

final class DailyReportJob extends CronJob {
  DailyReportJob()
    : super(
        name: 'daily-report',
        schedule: Schedule.parse('0 8 * * *'), // 8:00 AM daily
      );

  @override
  Future<void> run() async {
    // job logic here
  }
}

DailyReportJob main() => DailyReportJob();
```

## Constructor Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `name` | `String` | Yes | — | Unique identifier; used in `_cron_jobs` history and `zonai cron run <name>` |
| `schedule` | `Schedule` | Yes | — | When to run |
| `strict` | `bool` | No | `true` | Whether to skip missed runs (see below) |
| `runOnStartup` | `bool` | No | `false` | Run once immediately at server startup |
| `enabled` | `bool` | No | `true` | Set to `false` to disable without deleting the file |

## Schedule

Schedules use standard 5-field cron syntax via `Schedule.parse('...')`:

```dart
Schedule.parse('0 3 * * *')    // every day at 3:00 AM
Schedule.parse('*/15 * * * *') // every 15 minutes
Schedule.parse('0 9 * * 1')    // every Monday at 9:00 AM
Schedule.parse('0 0 1 * *')    // first of every month at midnight
```

Quick reference: `minute hour day-of-month month day-of-week`. Use [crontab.guru](https://crontab.guru) to build expressions.

## strict

- `strict: true` (default) — only run on the configured schedule. Missed runs are skipped.
- `strict: false` — if runs were missed while the server was offline, catch up immediately on next startup.

See [Catch-Up Logic](/cron-jobs/catch-up-logic) for details.

## runOnStartup

When `true`, the job fires once on server start regardless of its schedule. Useful for initialization tasks or ensuring a cleanup always runs after a deployment.

## The run() Method

Write job logic in `run()`. The `get`, `mutate`, `email`, and `logger` globals are all available:

```dart
@override
Future<void> run() async {
  final rows = await get.many(
    tableName: 'subscriptions',
    where: Lt('expires_at', DateTime.now()),
  ) ?? [];

  logger.info('Found ${rows.length} expired subscriptions');

  for (final row in rows) {
    mutate.update.one(
      table: 'subscriptions',
      updates: [Update.column('status', .literal('expired'))],
      where: Eq('id', row['id']),
    );
  }
}
```

Errors thrown from `run()` are caught, logged to `_cron_jobs`, and do not crash the server.
