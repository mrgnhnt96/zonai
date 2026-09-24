---
title: Rate Limiting Overview
description: How Zonai throttles requests per IP address and per table.
---

Zonai tracks requests per client IP address, per table, per operation (`get`, `create`, `signIn`, and so on). When a client exceeds the configured limit within a time window, further requests receive a `429 Too Many Requests` response until the window resets.

Rate limiting is the first check a request meets. It runs before rules, extensions or SQL, so a throttled request costs the server almost nothing.

<Info>

Stream routes share read policies: `getPolicy` → `/db/stream`, `limitPolicy` → `/db/stream/list`, `countPolicy` → `/db/stream/count`. Long-lived streams still count as requests when they open. See [Streaming](/operations/streaming).

</Info>

## Default Policy

**Every table is rate limited with no configuration.** Without a rate limit file, every operation on every table is limited to **100 requests per minute per IP**. A few auth routes default to tighter limits; see [Auth Rate Limits](/rate-limiting/auth-rate-limits).

You only write a rate limit file to change those numbers.

## Where to Configure

Create a file in `rateLimitPath` (default `lib/src/rate_limit`, set in [`zonai.yaml`](/configuration/zonai-yaml)), for example `task_rate_limits.dart`. Extend `TableRateLimits` (or `AuthTableRateLimits` for auth tables), override the methods you want to change, and export a `main()`:

```dart
import 'package:my_app/src/schemas/tasks.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class TaskRateLimits extends TableRateLimits<TaskTable, Task> {
  TaskRateLimits() : super(tasks);

  @override
  Future<RateLimitPolicy?> createPolicy() async =>
      const RateLimitPolicy(maxRequests: 10, window: Duration(minutes: 1));
}

TaskRateLimits main() => TaskRateLimits();
```

`TableRateLimits` is generic over the table and its row type, and its
constructor takes the table itself — the same `tasks` value you registered with
`table(...)`. Every policy method is asynchronous and returns
`Future<RateLimitPolicy?>`; returning `null` disables limiting for that
operation.

- **One class of each kind per table.** With a second `TableRateLimits` (or a second `AuthTableRateLimits`) for the same table, every rate limit check fails with `... rate limits already registered for <table>`, and so does every request that needs one.
- **An auth table can have both.** `AuthTableRateLimits` covers its auth routes only. Its `/db` reads and writes use a separate `TableRateLimits` for the same table, or the default if there is none.
- **Compiling runs `dart analyze` first.** `zonai serve` recompiles when a file under `rateLimitPath` changes. A missing or empty directory is fine; the defaults apply.

## How the Window Works

The window is **fixed**; it does not slide. It opens with the first counted request from an IP for a table and operation, and it closes `window` later. The first request after that opens a new window.

Refused requests are **not** counted and do **not** extend the window. With `maxRequests: 10, window: Duration(minutes: 15)`, ten requests at 12:00 use up the window, and the eleventh is refused until 12:15 however many times the client retries in between.

Counters live in the internal `_rate_limit` table. You do not create it; the built-in `_delete_old_rate_limits` cron job clears out old counters.

## The 429 Response

```text
HTTP/1.1 429 Too Many Requests
retry-after: 42
x-ratelimit-limit: 100
x-ratelimit-remaining: 0
x-ratelimit-reset: 1788307242
content-type: application/json

{"error":"Rate limit exceeded","collection":"items","operation":"create","retryAfter":42}
```

| Header                  | Value                                                                              |
| ----------------------- | ---------------------------------------------------------------------------------- |
| `Retry-After`           | Whole seconds until the window resets, rounded **up** and never `0`               |
| `X-RateLimit-Limit`     | The policy's `maxRequests`                                                         |
| `X-RateLimit-Remaining` | `0`                                                                                |
| `X-RateLimit-Reset`     | When the window resets, as a Unix timestamp in whole seconds (UTC)                 |

The body names the policy that was hit, so a client throttled on `create` knows it can keep reading:

- **`collection`**: the table the request targeted, or a shared bucket for routes that carry no table, such as `__auth_confirm__` for `POST /auth/confirm`. The full list is in [Auth Rate Limits](/rate-limiting/auth-rate-limits#endpoints-that-carry-no-table).
- **`operation`**: the operation name (`get`, `create`, `signIn`, `custom`, ...).
- **`customOperation`**: only on `PATCH /db/custom/:operation`, when the name could be validated. See [Configuring Policies](/rate-limiting/configuring-policies#when-operation-is-null).
- **`retryAfter`**: the same number as the `Retry-After` header.

Wait `Retry-After` seconds, then retry once. Every client behind one IP shares the same window and the same reset time, so several clients on one address should all wait for `X-RateLimit-Reset` instead of each retrying on its own schedule.

The rate limit headers are sent on the 429 only; successful responses do not carry them. Through 0.9.0 the body was the plain string `Rate limit exceeded`; match on the `429` status or the `error` field rather than the whole body.

<Info>

A `503 Service Unavailable` with `Retry-After: 1` is not a rate limit. It means the server's write queue or read capacity is full, for everyone rather than for your IP. See [Request Pipeline](/core-concepts/request-pipeline).

</Info>

## Client IP Resolution

By default, Zonai reads the client IP from the TCP connection. Behind a reverse proxy or load balancer, that is the proxy's IP, so every client shares one counter. Configure `AppConfig.trustedProxy` to read the real IP from a forwarded header. See [Trusted Proxies](/rate-limiting/trusted-proxies).

## Related

- [Configuring Policies](/rate-limiting/configuring-policies)
- [Auth Rate Limits](/rate-limiting/auth-rate-limits)
- [Trusted Proxies](/rate-limiting/trusted-proxies)
- [Streaming (Live Queries)](/operations/streaming) — stream routes share get/list/count policies
