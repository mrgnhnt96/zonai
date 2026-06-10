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

```dart
// Default — skip missed runs (suitable for cleanup jobs)
CronJob(name: 'cleanup', schedule: Schedule.parse('0 3 * * *'))

// Explicit skip
CronJob(name: 'cleanup', schedule: Schedule.parse('0 3 * * *'), strict: true)

// Catch up missed runs (suitable for billing jobs)
CronJob(name: 'billing', schedule: Schedule.parse('0 0 1 * *'), strict: false)
```

## How Catch-Up Works

On startup, Zonai checks `_cron_jobs` for the last successful run of each `strict: false` job. If any scheduled runs were missed since then, it executes the job once before resuming the normal schedule — regardless of how many runs were missed.

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

Even if the server was down for days, a `strict: false` job only runs once on catch-up.

## runOnStartup vs. strict: false

Both can trigger a run at startup but for different reasons:

- `runOnStartup: true` — always runs once on startup, regardless of whether any runs were missed
- `strict: false` — only runs on startup if scheduled runs were actually missed

They can be combined: `strict: false, runOnStartup: true` — catches up missed runs AND runs once unconditionally at startup.
