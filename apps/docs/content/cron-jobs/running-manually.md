---
title: Running Jobs Manually
description: How to trigger a cron job on demand without waiting for its schedule.
---

Cron jobs can be invoked by their `name` property — the same value passed to the `CronJob` constructor. Two ways to trigger a run outside the schedule:

## Dev TUI

In `zonai dev`, press **`j`** to open **Run cron job**, then select a job by name from the list.

```sh
zonai dev
```

The crons worker must be compiled (`zonai compile`, or press **`c`** in the TUI). Output from `logger` calls appears in the TUI panel. The run is recorded in `_cron_jobs` with its status and duration.

## HTTP API

While the server is running, admins can invoke a job by name over HTTP:

```sh
curl -X POST 'http://localhost:8080/crons/run?name=cleanup-old-logs' \
  -H 'Authorization: Bearer <admin-jwt>'
```

Requires an admin JWT. The job runs in the cron worker and is recorded in `_cron_jobs` like a scheduled run. If no job matches the given `name`, the API returns an error.

## When to Use

- Testing a new job before its first scheduled run
- Recovering from a missed run when catch-up (`strict: false`) isn't configured
- Ad-hoc data maintenance or backfill
- Debugging: force a run to see what the job logs and mutates

## Behavior

The run executes in the cron worker process. Output from `logger` calls is forwarded to the server console (visible in the dev TUI or server logs). The run is recorded in `_cron_jobs` with its status and duration.
