---
title: Rate Limiting Overview
description: How Zonai throttles requests per IP address and per table.
---

Zonai tracks requests per client IP address, per table, per operation. When a client exceeds the configured limit within a time window, subsequent requests receive a `429 Too Many Requests` response.

Rate limiting runs in the pipeline **after rules pass but before operations execute** — a throttled request consumes no SQL resources.

<Info>

Stream routes share read policies: `getPolicy` → `/db/stream`, `limitPolicy` → `/db/stream/list`, `countPolicy` → `/db/stream/count`. Long-lived streams still count as requests when they open. See [Streaming](/operations/streaming).

</Info>

## Default Policy

If no rate limit file exists for a table, a default policy of **100 requests per minute per IP** applies to all operations.

## Where to Configure

Create a file in `rateLimitPath` named `<table>_rate_limits.dart`. Extend `TableRateLimits` (or `AuthTableRateLimits` for auth tables) and override the methods you want to customize:

```dart
import 'package:zonai_schema/zonai_schema.dart';

final class TaskRateLimits extends TableRateLimits {
  @override
  RateLimitPolicy? createPolicy() =>
      RateLimitPolicy(maxRequests: 10, window: Duration(minutes: 1));
}

TaskRateLimits main() => TaskRateLimits();
```

## Client IP Resolution

By default, Zonai reads the client IP from the TCP connection. Behind a reverse proxy or load balancer, this would be the proxy IP rather than the real client IP. Configure `AppConfig.trustedProxy` to read the real IP from a forwarded header. See [Trusted Proxies](/rate-limiting/trusted-proxies).

## Related

- [Configuring Policies](/rate-limiting/configuring-policies)
- [Auth Rate Limits](/rate-limiting/auth-rate-limits)
- [Trusted Proxies](/rate-limiting/trusted-proxies)
- [Streaming (Live Queries)](/operations/streaming) — stream routes share get/list/count policies
