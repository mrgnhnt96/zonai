---
title: Metrics & Cron Jobs
description: The dashboard landing screen — request volume, error rate, active sessions, and cron job status with manual runs.
---

The landing screen at **`/_`** answers "is the server healthy, and what has it
been doing?" Everything on it is computed from the server's own request log and
job history — there is no external metrics service to configure.

## The numbers

Four figures sit across the top, all over a rolling **24-hour** window:

| Tile | What it counts |
| --- | --- |
| **Requests (24h)** | Total requests handled |
| **Error Rate** | Share of those requests that failed |
| **Active Sessions** | Sessions currently valid |
| **Tables** | Tables in the database |

Underneath, **Requests over time** breaks the same 24 hours into hourly
buckets, so a traffic spike or an outage is visible as a shape rather than a
single number.

<Info>

**Exclude admin** filters your own dashboard traffic out of the figures.
Leave it on when you are trying to read real user activity — otherwise
browsing tables inflates the request count you are looking at.

</Info>

## Top Errors (24h)

The failures from the same window, grouped so the repeated ones rise to the
top rather than scrolling past one at a time. When nothing has failed, the
panel says so — **No errors in the last 24h** is a useful thing to be able to
confirm at a glance.

For the full log rather than the summary, use [`zonai db`](/cli/db).

## Cron Jobs

Every job [defined in your project](/cron-jobs/defining-a-job) is listed with
its most recent outcome:

| State | Meaning |
| --- | --- |
| **Succeeded** | Last run completed |
| **Failed** | Last run threw |
| **Running** | Currently executing |
| **Never run** | Defined, but not yet triggered |

**Run** triggers a job immediately, without waiting for its schedule. That is
the fastest way to check a job you have just written, and it is the same
manual trigger described in [Running Manually](/cron-jobs/running-manually) —
so the usual caution applies: the job does real work against real data.

A refresh control re-reads job state without reloading the page, which is
useful while watching a long job finish.

<Info>

A job that mutates rows will also push updates to any open
[live queries](/operations/streaming) watching those rows — including a table
open in another dashboard tab.

</Info>

## Related

- [Cron Jobs Overview](/cron-jobs/overview) — how scheduled jobs are compiled and run
- [Catch-Up Logic](/cron-jobs/catch-up-logic) — what happens to runs missed while the server was down
- [Browsing & Editing Data](/dashboard/table-editor) — inspecting the rows a job touched
