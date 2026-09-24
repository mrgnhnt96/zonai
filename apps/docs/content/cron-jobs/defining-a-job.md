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

- **One job per file.** Every `.dart` file under `cronsPath` is compiled in, including files in subdirectories, and each one's `main()` must return a `CronJob`.
- **The constructor is not `const`.** `Schedule.parse` is not a const constructor, so a job built from it cannot be `const` either.
- **Keep `name` unique.** Catch-up and run history look jobs up by `name`, and manual runs start the first job with a matching name. Two jobs with the same name share one history.

## Constructor Parameters

| Parameter      | Type       | Required | Default | Description                                                                                                 |
| -------------- | ---------- | -------- | ------- | ----------------------------------------------------------------------------------------------------------- |
| `name`         | `String`   | Yes      | —       | Unique identifier; used in `_cron_jobs` history and on-demand invocation by name (dev TUI or `POST /crons/run?name=<name>`) |
| `schedule`     | `Schedule` | Yes      | —       | When to run                                                                                                 |
| `strict`       | `bool`     | No       | `true`  | `true` skips ticks missed while the server was down; `false` catches up once on startup                     |
| `runOnStartup` | `bool`     | No       | `false` | Run once immediately when the crons worker starts                                                           |
| `enabled`      | `bool`     | No       | `true`  | **Not enforced yet.** The scheduler runs the job whatever this is set to, so delete or move the file to stop a job |

## Schedule

Schedules use standard cron syntax via `Schedule.parse('...')`:

```dart in:expression
Schedule.parse('0 3 * * *'),    // every day at 3:00 AM
Schedule.parse('*/15 * * * *'), // every 15 minutes
Schedule.parse('0 9 * * 1'),    // every Monday at 9:00 AM
Schedule.parse('0 0 1 * *'),    // first of every month at midnight
```

Quick reference: `minute hour day-of-month month day-of-week`. A sixth, leading field adds seconds. Use [crontab.guru](https://crontab.guru) to build expressions. Times are the server's local time.

You can also build a schedule from explicit fields:

```dart in:expression
Schedule(minutes: [0, 30], hours: [9, 17], weekdays: [1, 2, 3, 4, 5]),
```

`Schedule` comes from the [`cron` package](https://pub.dev/packages/cron), which `package:zonai_schema/zonai_schema.dart` re-exports. That package's docs cover the full field syntax (`*`, lists, ranges, steps).

## strict

- `strict: true` (default): the job runs only on its schedule. Ticks missed while the server was down are skipped.
- `strict: false`: if a tick was missed since the job's last recorded run, the job runs once as soon as the crons worker starts.

See [Catch-Up Logic](/cron-jobs/catch-up-logic) for details.

## runOnStartup

When `true`, the job runs once as soon as crons start with the server, whatever its schedule says. Useful for initialization tasks or for making sure a cleanup always runs after a deployment.

## The run() Method

Write job logic in `run()`. The `get`, `mutate`, `email`, `push` and `logger` globals are all available (see [Side Effects in Cron Jobs](/cron-jobs/side-effects)):

```dart in:cron-run
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
      where: Eq('id', row['id']!),
    );
  }
}
```

Errors thrown from `run()` are caught and recorded on the run's `_cron_jobs` row (`failed`, `error`, `stack_trace`). They do not crash the server.
