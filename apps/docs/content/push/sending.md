---
title: Sending
description: Naming a recipient set with a query, where to call push from, and what the returned job id promises.
---

```dart in:side-effects
final job = await push(
  PushMessage(
    title: 'New reply',
    body: 'Someone replied to your post',
    collapseKey: 'post:${after.id}',
    data: {'postId': '${after.id}'},
  ),
  table: 'device_tokens',
  column: 'token',
  platformColumn: 'platform',
  where: In('user_id', recipientIds),
);

logger.info('queued push job ${job.value}');
```

## You name a set, not a list

`where` is a query Zonai runs and pages. This is the difference between sending to a hundred thousand recipients and holding a hundred thousand tokens in memory before the first send.

It also means a segment is expressible directly — `active = true and locale = 'en'` — without your code running the query, reading the rows, and handing back a list of strings.

The fan-out reads **only the primary key, the token column, and the platform column when you name one** — whatever the `where` says. That is a security property rather than an optimisation: the recipient query deliberately skips per-row rules, so a wider projection would turn `push` into a way to read columns the caller could not otherwise read. It is also why `platformColumn` is a parameter rather than something Zonai discovers: widening the projection stays the caller's explicit decision.

`platformColumn` is optional, and what omitting it means depends on your configuration. With FCM configured, every recipient goes through FCM — the setup Zonai shipped with, and still correct. **With APNs only, omitting it means nothing can be routed at all**, because FCM is the fallback and it is not there; those recipients fail transiently and forever. Name it and iOS goes straight to APNs. See [Device Tokens](/push/device-tokens) for the values it accepts and what an unroutable recipient looks like.

## Call it from `after*` hooks, never `before*`

A `before` hook runs prior to the write. A notification announcing something that then does not happen cannot be recalled. This is the first thing to get right and the easiest to get wrong.

- **Enqueuing is transactional.** The job row is committed with your request.
- **Sending is not.** Once the fan-out starts, nothing about the request can stop it.
- **Throwing from an `after` hook fails the request after the write has committed.** A job already enqueued still runs.

## `PushMessage`

| Field | |
|---|---|
| `title`, `body` | What the person sees. |
| `collapseKey` | Replaces an earlier undelivered notification carrying the same key instead of stacking beside it — `collapseKey` on FCM, `apns-collapse-id` on APNs. **Set this on anything sent from a fan-out** — see [Delivery Guarantees](/push/delivery-guarantees). |
| `data` | `Map<String, String>`. FCM's data values are strings; typing it wider invites a silent `toString()` at the transport, and a number that arrives as `"1"` on the device is a bug nobody can see from the server. |

`data` is where a deep link goes — the ids the app needs to open the right screen when someone taps the notification.

### Size is checked at enqueue, not at send

FCM's documented payload ceiling is **4096 bytes**, and Zonai refuses a message that does not fit — minus a 512-byte allowance for what the transport adds per recipient: the registration token, the platform blocks a collapse key expands into, and the JSON envelope around all of it.

The check happens at the `push` call, which is the whole point. An over-limit payload comes back from FCM as `INVALID_ARGUMENT` — *the same status it uses for a dead token* — so left to the transport, one oversized message looks exactly like every recipient's registration going bad at once. Failing at the call site means the author is told before a job exists, and the error names the byte count and the budget.

A notification body is truncated on screen well before this limit anyway. If you are near it, the detail belongs in the app, not the payload.

## What the job id means

`push` returns a `PushJobId` as soon as the job is **durably recorded**. That takes a few milliseconds whether the recipient set is ten rows or a hundred thousand, which is what makes it safe to `await` inside a request-path hook.

It is **not**:

- a promise the notification was delivered — FCM offers no such receipt to anyone;
- awaitable to completion. There is no "wait for the fan-out", and there will not be one. By the time a large fan-out finishes, the request that started it returned long ago.

What the id is good for is querying the jobs collection: progress, per-outcome counts (delivered, permanently rejected, transiently failed), and the reason a job failed. That collection is admin-gated like every other framework-owned table — a job row carries the notification body and the recipient predicate — so read it with an admin identity rather than from a user request.

## When sending actually happens

Enqueuing starts a drain immediately, so a notification does not wait for a timer. An internal cron runs every minute as the **resume** path: a fan-out whose drain died mid-batch, or one enqueued by a process that has since restarted, is picked up there.

A second internal cron purges *finished* jobs nightly, after seven days. Running and pending jobs are never purged by age — a running job's row is its cursor, and deleting it would restart its fan-out from the top.
