---
title: Delivery Guarantees
description: At-least-once with duplicates bounded by one batch, why exactly-once is not available, and the case where a recipient is not retried at all.
---

**The fan-out is at-least-once. Duplicates are bounded by one batch. Exactly-once is not available.**

Reading that sentence carefully is worth more than any other page here.

## Why not exactly-once

FCM exposes no idempotency key for `messages:send`. A send that succeeds remotely and crashes before its outcome is committed will be retried, and FCM has no way to recognise it as the same message. Going direct to APNs changes nothing here: a collapse id replaces a notification *on the device*, which is not the same thing as a service refusing a duplicate send.

So the batch size is also the blast radius of a crash: at `batchSize: 500`, a crash at the wrong moment can re-notify up to 500 people. That is the trade the number encodes, and it is why [Configuration](/push/configuration) calls it three things at once.

## What bounds it

**Checkpointing.** Each batch's outcomes, prunes and cursor commit in a single transaction. A crash anywhere resumes at the last committed batch boundary rather than at the top of the recipient set.

The paging is keyset — `WHERE pk > cursor ORDER BY pk` — never `OFFSET`. `OFFSET` degrades linearly across a scan and, worse, silently skips or repeats rows when the table is written to mid-scan. It will be: devices register while a fan-out is running.

**Collapse keys.** A duplicate carrying the same `collapseKey` *replaces* the earlier notification on the device instead of stacking beside it — FCM calls it `collapseKey`, APNs calls it `apns-collapse-id`, and Zonai sets whichever the recipient's transport wants. This is the only mechanism that makes a duplicate invisible to the person holding the phone, rather than merely rare. Set one on anything sent from a fan-out.

## The other side of the trade

**A transient failure inside a committed batch is not retried by a later pass.**

Retries happen *within* a batch — `maxAttemptsPerBatch`, with exponential backoff on `429` and `5xx`. Once that batch commits, the cursor has moved past it, and re-reading it would re-send to everyone else in the batch too.

So a recipient counted in `transiently_failed` did not get the message, and nothing will try again. This is the direct consequence of checkpointing at batch granularity, and it is stated here rather than left to be discovered from a support ticket.

If that count is non-zero and matters to you, the job row is where you find out. Re-sending is your decision, because only you know whether the notification is still worth sending an hour later.

## What "delivered" means

`delivered` on a job row means **the transport accepted the message** — FCM answered `200`, or APNs did. It does not mean:

- the device received it — the phone may be off, or offline for days;
- the person saw it — notifications are dismissible and collapsible;
- the app processed it — a data payload can be dropped by the OS under memory pressure.

No push service offers a real delivery receipt, so nothing above this layer can either. Treat push as a prompt to open the app, never as a transport for state the app cannot reconstruct on its own.

## Ordering

There is none across batches, and none within one — a batch sends concurrently. Two notifications sent in quick succession can arrive in either order. If order matters, put a sequence number in `data` and let the app sort, or collapse them into one message.
