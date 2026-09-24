---
title: Running Jobs Manually
description: How to trigger a cron job on demand without waiting for its schedule.
---

Cron jobs can be invoked by their `name` property, the same value passed to the `CronJob` constructor. The name must match exactly. There are two ways to trigger a run outside the schedule.

## Dev TUI

In `zonai dev`, press **`j`** to open **Run cron job**, then select a job by name from the list.

```sh
zonai dev
```

The crons worker must be compiled (`zonai compile`, or press **`c`** in the TUI). Output from `logger` calls appears in the TUI panel.

## HTTP API

While the server is running, an admin can list the jobs and invoke one by name:

```sh
# Every job name the crons worker knows, built-in `_` jobs included
curl 'http://localhost:8080/crons/list' \
  -H 'Authorization: Bearer <admin-jwt>'
# {"names": ["_cleanup_logs", ..., "cleanup-old-logs"]}

curl -X POST 'http://localhost:8080/crons/run?name=cleanup-old-logs' \
  -H 'Authorization: Bearer <admin-jwt>'
```

Both routes require an admin JWT; any other caller is refused with an access-denied error.

`POST /crons/run` waits for the job to finish before it responds. It succeeds only if `run()` returned without throwing. If `run()` throws, or no job has that `name`, the request fails with an error status. The server log records which of the two happened.

## When to Use

- Testing a new job before its first scheduled run
- Recovering from a missed run when catch-up (`strict: false`) isn't configured
- Ad-hoc data maintenance or backfill
- Debugging: force a run to see what the job logs and mutates

## Behavior

A manual run behaves like a scheduled one. It runs as `CronJwt`, its queued `mutate` calls are committed the same way, and it gets its own `_cron_jobs` row with `started` and either `completed` or `failed`. Output from `logger` calls is forwarded to the server log.
