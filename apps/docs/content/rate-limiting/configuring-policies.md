---
title: Configuring Policies
description: Setting custom rate limit policies per table and per operation.
---

## TableRateLimits

Extend `TableRateLimits<S, R>` in `<table>_rate_limits.dart`. Pass the schema ref to `super()` and override methods as needed. Unoverridden operations use the default policy (100 req/min per IP).

```dart
import 'package:my_app/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class PostRateLimits extends TableRateLimits<PostTable, Post> {
  PostRateLimits() : super(posts);

  @override
  Future<RateLimitPolicy?> createPolicy() async =>
      const RateLimitPolicy(maxRequests: 10, window: Duration(minutes: 1));

  @override
  Future<RateLimitPolicy?> getPolicy() async =>
      const RateLimitPolicy(maxRequests: 1000, window: Duration(minutes: 1));

  @override
  Future<RateLimitPolicy?> limitPolicy() async =>
      const RateLimitPolicy(maxRequests: 500, window: Duration(minutes: 1));
}

PostRateLimits main() => PostRateLimits();
```

## RateLimitPolicy

```dart no-analyze
RateLimitPolicy(maxRequests: N, window: Duration(...))
```

- `maxRequests` — number of requests allowed per IP, per table and operation, within one window
- `window` — the length of one **fixed** window. It starts at the first counted request and resets `window` later; refused requests do not extend it. See [How the Window Works](/rate-limiting/overview#how-the-window-works).

`RateLimitPolicy.defaultPolicy` is the built-in 100 requests per minute. Return it (`.defaultPolicy`) to keep the default for one case while overriding others.

## Per-Operation Methods

All methods are `async` and return `Future<RateLimitPolicy?>`. Paths use a JSON `table` in the body (or `?body=`), not a path segment.

| Method | Endpoints |
|--------|----------|
| `createPolicy()` | `POST /db`, `POST /db/many` |
| `updatePolicy()` | `PATCH /db`, `PATCH /db/many` |
| `deletePolicy()` | `DELETE /db`, `DELETE /db/many` |
| `getPolicy()` | `GET /db`, `GET /db/stream` |
| `limitPolicy()` | `GET /db/list`, `GET /db/stream/list` |
| `countPolicy()` | `GET /db/count`, `GET /db/stream/count` |
| `customPolicy(operation)` | `PATCH /db/custom/:operation`, `PATCH /db/custom/:operation/many` |

Streaming shares the read policies above. Details: [Streaming](/operations/streaming).

A `/many` request counts as **one** request against the policy, however many rows it carries.

Methods you do not override keep the default: `PostRateLimits` above overrides only `createPolicy`, `getPolicy` and `limitPolicy`, so `count`, `update`, `delete` and custom operations on `posts` stay at 100 per minute.

`customPolicy` buckets separately per operation name (`fill` and `reserve` on the same table get independent counters), but only for a name that's actually registered in that table's rules — an unrecognized `:operation` is rejected with `404` before it ever reaches the rate limiter:

```dart in:rate-limits
@override
Future<RateLimitPolicy?> customPolicy(String? operation) async {
  return switch (operation) {
    'fill' => const RateLimitPolicy(maxRequests: 20, window: Duration(minutes: 1)),
    // Name unavailable -- one counter shared by every custom operation.
    null => const RateLimitPolicy(maxRequests: 60, window: Duration(minutes: 1)),
    _ => .defaultPolicy,
  };
}
```

### When `operation` is `null`

Validating the name requires the table's rules, and the server can only read those without an IPC round-trip when rules are linked into the binary. When they aren't — a binary built without a project link, or `ZONAI_FORCE_WORKERS=1` — the name arrives unvalidated, and trusting it would hand callers a bypass: every new name they invent starts on a fresh counter.

So in that case the server drops the name rather than the limit. `operation` is `null`, all custom operations on the table share one counter, and the `404` for an unregistered name is skipped — the rules layer still denies it, just later in the request. Handle `null` if you want that shared counter to differ from `defaultPolicy`.

## Disabling Rate Limiting for an Operation

Return `null` to remove rate limiting for that operation entirely:

```dart in:rate-limits
@override
Future<RateLimitPolicy?> getPolicy() async => null; // No limit on view requests
```

## Example: Different Limits for Reads and Writes

```dart
import 'package:my_app/src/schemas/articles.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class ArticleRateLimits extends TableRateLimits<ArticleTable, Article> {
  ArticleRateLimits() : super(articles);

  // Strict limits for writes
  @override
  Future<RateLimitPolicy?> createPolicy() async =>
      const RateLimitPolicy(maxRequests: 5, window: Duration(minutes: 1));

  @override
  Future<RateLimitPolicy?> updatePolicy() async =>
      const RateLimitPolicy(maxRequests: 20, window: Duration(minutes: 1));

  @override
  Future<RateLimitPolicy?> deletePolicy() async =>
      const RateLimitPolicy(maxRequests: 5, window: Duration(minutes: 1));

  // Relaxed limits for reads
  @override
  Future<RateLimitPolicy?> getPolicy() async =>
      const RateLimitPolicy(maxRequests: 2000, window: Duration(minutes: 1));

  @override
  Future<RateLimitPolicy?> limitPolicy() async =>
      const RateLimitPolicy(maxRequests: 1000, window: Duration(minutes: 1));
}

ArticleRateLimits main() => ArticleRateLimits();
```
