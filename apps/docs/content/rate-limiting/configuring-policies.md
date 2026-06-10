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

```dart
RateLimitPolicy(maxRequests: N, window: Duration(...))
```

- `maxRequests` — number of requests allowed per IP within the window
- `window` — the sliding time window

## Per-Operation Methods

All methods are `async` and return `Future<RateLimitPolicy?>`.

| Method | Endpoint |
|--------|----------|
| `createPolicy()` | `POST /db/<table>` |
| `updatePolicy()` | `PATCH /db/<table>/:id` |
| `deletePolicy()` | `DELETE /db/<table>/:id` |
| `getPolicy()` | `GET /db/<table>/:id` |
| `limitPolicy()` | `GET /db/<table>/list` |
| `countPolicy()` | `GET /db/<table>/count` |

## Disabling Rate Limiting for an Operation

Return `null` to remove rate limiting for that operation entirely:

```dart
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
