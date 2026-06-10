---
title: Running Jobs Manually
description: How to trigger a cron job on demand without waiting for its schedule.
---

## Command

```sh
zonai cron run <name>
```

Triggers a cron job immediately by its `name` property, without waiting for its schedule.

```sh
zonai cron run cleanup-old-logs
zonai cron run daily-report
```

## When to Use

- Testing a new job before its first scheduled run
- Recovering from a missed run when catch-up (`strict: false`) isn't configured
- Ad-hoc data maintenance or backfill
- Debugging: force a run to see what the job logs and mutates

## Behavior

The command waits for the job to complete. Output from `logger` calls in the job is printed to the terminal. The run is recorded in `_cron_jobs` with its status and duration.

## No Server Required

`zonai cron run` spawns the compiled crons worker as a subprocess directly — it does not connect to a running server. The crons worker must be compiled (either via `zonai compile` or `zonai serve` in dev mode), but the HTTP server does not need to be running:

```sh
# Compile workers if not already done
zonai compile

# Then run the job directly
zonai cron run cleanup-old-logs
```

## Flags

Use `--flavor` to target a specific config flavor:

```sh
zonai cron run daily-report --flavor prod
```
