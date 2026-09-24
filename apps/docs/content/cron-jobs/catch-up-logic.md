---
title: Catch-Up Logic
description: What happens to scheduled jobs when the server is offline.
---

## The strict Property

`strict` controls what happens when scheduled runs are missed (e.g. the server was offline):

| Value           | Default? | Behavior                                                            |
| --------------- | -------- | ------------------------------------------------------------------- |
| `strict: true`  | Yes      | **Skip** missed runs — only run on the future schedule              |
| `strict: false` | No       | **Catch up** — execute once on next startup if any runs were missed |

`strict` is passed to `super` in the job's constructor. It defaults to `true`,
so a cleanup job that should skip missed runs can leave it out entirely; a
billing job that must catch up passes `false`:

```dart in:project-file
final class BillingJob extends CronJob {
  BillingJob()
    : super(
        name: 'billing',
        schedule: Schedule.parse('0 0 1 * *'),
        strict: false, // catch up if runs were missed
      );

  @override
  Future<void> run() async {
    // ...
  }
}

BillingJob main() => BillingJob();
```

## How Catch-Up Works

When crons start, Zonai looks up the most recent run of each `strict: false` job in `_cron_jobs`. It uses the most recent run whether that run completed or failed. If at least one scheduled tick fell between that run and now, the job runs once before resuming its normal schedule. It runs once no matter how many ticks were missed.

A job with no `_cron_jobs` history has nothing to compare against, so its first run waits for its first scheduled tick. Add `runOnStartup: true` if it should run immediately the first time.

Catch-up is checked only when crons start, which happens when the server starts.

## When to Use Each

**`strict: true` (skip)** is appropriate for:

- Periodic cleanups where missing one run causes no harm
- Metrics aggregation that is idempotent from the start of the next window
- Any job where the work is naturally re-done at the next scheduled time

**`strict: false` (catch up)** is appropriate for:

- Billing cycles — must process every interval
- Report generation where each run produces a distinct artifact
- Any job where skipping a run has business consequences

## Cautions

Even if the server was down for days, a `strict: false` job only runs once on catch-up. A billing job that must process every missed period has to work out which periods are outstanding itself, for example from its own records or from `_cron_jobs`.

## runOnStartup vs. strict: false

Both can trigger a run at startup but for different reasons:

- `runOnStartup: true` always runs once on startup, whether or not any ticks were missed
- `strict: false` runs on startup only if a scheduled tick was actually missed

Setting both is the same as `runOnStartup: true` alone. The job runs once on startup and the catch-up check is skipped, so it never runs twice.
