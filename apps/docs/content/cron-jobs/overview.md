---
title: Cron Jobs Overview
description: What cron jobs are and how they run in Zonai.
---

Cron jobs are scheduled background tasks that run on a timer, independent of HTTP requests. Write them in Dart, and Zonai compiles them into the crons worker.

Use cron jobs for: purging old data, sending periodic digests, flagging stale records, running maintenance tasks. For work that should react to a create, update, delete or sign-in, use [extensions](/extensions/overview) instead.

<Info>

Cron mutations that change rows will also push updates to any open `/db/stream*` / `db.listen` subscriptions watching those queries. See [Streaming](/operations/streaming).

</Info>

## What You Need

1. A `.dart` file per job under `cronsPath` (default `lib/src/crons`, set in [`zonai.yaml`](/configuration/zonai-yaml)). Subdirectories are searched too.
2. In it, a class extending `CronJob` and a top-level `main()` returning an instance.
3. `zonai serve` (or `zonai dev`) running. It compiles the crons worker, starts it with the HTTP server, and recompiles when a file under `cronsPath` changes. `zonai compile` compiles it without serving.

```dart
import 'package:zonai_schema/zonai_schema.dart';

final class ExpireInvitesJob extends CronJob {
  ExpireInvitesJob()
    : super(name: 'expire-invites', schedule: Schedule.parse('0 3 * * *'));

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    mutate.delete.many(
      tableName: 'invites',
      where: Lt('created_at', cutoff),
    );
    logger.info('Queued deletion of invites older than $cutoff');
  }
}

ExpireInvitesJob main() => ExpireInvitesJob();
```

Compiling runs `dart analyze` over `cronsPath` first, and a single analyzer error stops the crons worker from compiling. See [Defining a Job](/cron-jobs/defining-a-job) for every constructor option.

## How Jobs Run

The cron worker runs each job on its configured `Schedule`. Stopping the server stops the worker.

**A job never overlaps itself.** If a job is still running when its next tick arrives, that tick is held until the current run finishes and then runs straight away. Several ticks missed during one long run are merged into a single extra run. Different jobs are scheduled independently and can run at the same time.

**Ticks missed while the server was down are skipped** by default. Set `strict: false` to catch up once on startup. See [Catch-Up Logic](/cron-jobs/catch-up-logic).

**Errors thrown from `run()` are caught.** The run is recorded as failed in `_cron_jobs` and logged. The server stays up and the job runs again on its next tick.

## The CronJwt Identity

Everything a job does through `get`, `mutate`, `email` and `push` runs as `CronJwt`, an internal system identity with admin edit access. You never pass it yourself. Rules and row rules still run against it, so a rule that refuses admin identities refuses your cron too.

`CronJwt` is not a session token. It is never issued to a client, and an HTTP request cannot present it as a bearer token.

## The _cron_jobs Table

Zonai records each run in the internal `_cron_jobs` table:

| Column        | Meaning                                         |
| ------------- | ----------------------------------------------- |
| `name`        | The job's `name`                                |
| `started`     | When the run began                              |
| `completed`   | Set when `run()` returned without throwing      |
| `failed`      | Set when `run()` threw                          |
| `error`       | The thrown error, as a string                   |
| `stack_trace` | Its stack trace                                 |

Query it to audit job history or debug failures. Ordinary clients cannot read it. The server log also prints `[CRON] started: <name>`, `[CRON] completed: <name>` and `[CRON] failed: <name>` for every run. Rows older than 30 days are deleted by the built-in `_cleanup_cron_entries` job.

## Built-in Jobs

Zonai compiles its own maintenance jobs into the same worker. They show up in `_cron_jobs`, in the dev TUI job list and in `GET /crons/list`, next to yours. Their names start with `_`, so give your own jobs names without a leading underscore.

| Job                            | Schedule           | What it does                                                        |
| ------------------------------ | ------------------ | ------------------------------------------------------------------- |
| `_cleanup_logs`                | daily 03:00        | Deletes `_log` rows older than 4 days, then reclaims the freed disk |
| `_cleanup_auth_challenges`     | daily 03:15        | Deletes expired auth challenges (OTP codes, magic links, resets)    |
| `_cleanup_cron_entries`        | daily 03:30        | Deletes `_cron_jobs` rows older than 30 days                        |
| `_delete_expired_jwts`         | daily 04:00        | Deletes expired sessions (catches up after downtime)                |
| `_cleanup_push_jobs`           | daily 04:00        | Deletes finished push jobs older than 7 days                        |
| `_cleanup_unreferenced_photos` | daily 05:00        | Deletes photos no row references (catches up after downtime)        |
| `_delete_old_rate_limits`      | every 15 minutes   | Deletes `_rate_limit` counters whose window began over 7 days ago   |
| `_drain_push_jobs`             | every minute       | Advances queued [push](/push/overview) fan-outs                     |

`_cleanup_logs` finishes by asking the server to rewrite the log database, which is the step that gives the space back to the disk. It skips the rewrite when there is less than about 16 MB to reclaim. If the volume has too little free space for the copy the rewrite needs, the server logs how much space it needs, how much is free, and what to do about it. `zonai db logs clear --vacuum` does the same thing by hand.

## Running on Demand

Each job's `name` is how you trigger it without waiting for its schedule, as well as its key in `_cron_jobs`:

- **Dev TUI:** `zonai dev`, then press **`j`** to run a job by name
- **HTTP API:** `POST /crons/run?name=<name>` (admin JWT required)

See [Running Jobs Manually](/cron-jobs/running-manually) for details.

## Related

- [Defining a Job](/cron-jobs/defining-a-job)
- [Catch-Up Logic](/cron-jobs/catch-up-logic)
- [Side Effects in Cron Jobs](/cron-jobs/side-effects)
- [Running Jobs Manually](/cron-jobs/running-manually)
- [Workers](/core-concepts/workers)
