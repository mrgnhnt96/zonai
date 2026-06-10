---
title: zonai cron
description: Manually trigger a cron job by name.
---

Manually trigger a cron job on demand, without waiting for its scheduled time.

```sh
zonai cron run <name> [flags]
```

## cron run

```sh
zonai cron run cleanup-old-logs
zonai cron run daily-report --flavor prod
```

The command waits for the job to complete and prints its output. The run is recorded in `_cron_jobs` with status and duration.

The job `name` must exactly match the `name` property in the `CronJob` class. If not found, the command exits with an error.

## No Server Required

`zonai cron run` spawns the compiled crons worker as a subprocess directly — it does not connect to a running HTTP server. The crons worker must be compiled, but the server does not need to be running:

```sh
# Compile if needed
zonai compile

# Run the job
zonai cron run cleanup-old-logs
```

## When to Use

- Testing a new job before its first scheduled run
- Recovering from a missed run that `strict: false` didn't catch
- Ad-hoc data maintenance or backfill tasks
- Debugging: force a run to inspect what the job logs and mutates

See [Running Jobs Manually](/cron-jobs/running-manually) for more details.
