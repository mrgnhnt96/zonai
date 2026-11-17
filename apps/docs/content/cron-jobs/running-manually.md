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

While the server is running, an admin, or an [API token minted with `--crons`](/authentication/api-tokens#running-crons), can list the jobs and invoke one by name:

```sh
# Every job name the crons worker knows, built-in `_` jobs included
curl 'http://localhost:8080/crons/list' \
  -H 'Authorization: Bearer <admin-jwt>'
# {"names": ["_cleanup_logs", ..., "cleanup-old-logs"]}

curl -X POST 'http://localhost:8080/crons/run?name=cleanup-old-logs' \
  -H 'Authorization: Bearer <admin-jwt>'
# {"name": "cleanup-old-logs", "ok": true, "ms": 812,
#  "changes": {"logs": {"delete": 120}}}
```

Both routes take an admin JWT, or an API token whose scope names the job (`--crons`). A token sees in `/crons/list` only the jobs it may run, and is refused (`403`) on any other. Every other caller is refused.

`POST /crons/run` waits for the job to finish, and for its writes to be committed, before it responds. `changes` counts the rows it wrote by table and action: one per row created, and the rows each update or delete matched, including writes that hooks on those tables made in turn. A run that wrote nothing answers `"changes": {}`.

If `run()` throws, the request fails with `500`, and if no job has that `name`, with `404`. Either way the body is the same shape with `"ok": false` and an `"error"`; writes the job made before it threw are still committed and counted.

## When to Use

- Testing a new job before its first scheduled run
- Recovering from a missed run when catch-up (`strict: false`) isn't configured
- Ad-hoc data maintenance or backfill
- Debugging: force a run to see what the job logs and mutates

## Behavior

A manual run behaves like a scheduled one. It runs as `CronJwt`, its queued `mutate` calls are committed the same way, and it gets its own `_cron_jobs` row with `started` and either `completed` or `failed`. Output from `logger` calls is forwarded to the server log.
