---
title: "Side Effects: push"
description: Sending push notifications from extension hooks and cron jobs.
---

`push` sends a notification to every row of a table whose `deviceToken` column matches a query. `AppConfig.push` must be configured before anything is sent; without it the call throws. See [Push Configuration](/push/configuration).

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
  where: In('user_id', recipientIds),
);
```

## It is unlike the other side effects, in three ways

**It is awaited.** `mutate` queues a write and returns nothing; `push` returns a `PushJobId`. The wait is for the job row to be committed, not for the fan-out — a few milliseconds whether the recipient set is ten rows or a hundred thousand.

**The id is not a delivery receipt.** It says the job was written down. Nothing here, and nothing FCM offers, tells you a notification reached a phone. See [What the job id means](/push/sending#what-the-job-id-means).

**It outlives the request.** A queued `mutate` is committed with the request. A fan-out keeps running long after the response was sent, and nothing about the request can stop it once it starts.

## Call it from `after*` hooks, never `before*`

A `before` hook runs prior to the write. A notification announcing something that may not happen cannot be recalled — there is no unsend.

Throwing from an `after` hook fails the request after the write has committed, and a job already enqueued still runs.

## Recipients are a query, not a list

`where` is a predicate Zonai runs and pages, so a large recipient set is never materialized in memory. The column must be declared with `$.deviceToken(...)`: the fan-out reads only the primary key and that column, and refuses any column that is not one. See [Device Tokens](/push/device-tokens).

## Dead tokens are Zonai's job, not yours

When FCM reports a token permanently rejected, Zonai clears it and calls `onPushRejected` first — a hook on the extension for the table the token lives on, not something you request here. A timeout is *not* a dead token and never prunes. See [Dead Tokens](/push/dead-tokens).

## Related

- [Push Overview](/push/overview)
- [Sending](/push/sending)
- [Delivery Guarantees](/push/delivery-guarantees)
- [Side Effects: email](/extensions/side-effects-email)
