---
title: Keyed Counters
description: Limiting creates per API key, per device, or by any other column of the submitted row instead of per IP.
---

Every policy in [Configuring Policies](/rate-limiting/configuring-policies) counts per client IP address. That is the wrong unit when many honest callers share one address. A company's office, a school, or a mobile carrier's NAT can put hundreds of devices behind one IP, and together they use up a budget meant for one caller.

For creates, a table can count on a value from the submitted row instead, such as the row's API key or install id. It can also keep several counters at once, each with its own policy.

## Defining Counters

Override `createCounters()` on your `TableRateLimits` and return one `RateLimitCounter` per counter:

```dart
import 'package:my_app/src/schemas/uploads.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// API key to the app it belongs to. In a real project this would be a
/// lookup of your own.
const _apps = {'pk_live_acme': 'acme', 'pk_live_globex': 'globex'};

const _enterprise = {'acme'};

final class UploadRateLimits extends TableRateLimits<UploadTable, Upload> {
  UploadRateLimits() : super(uploads);

  // The counters below replace the per-IP one.
  @override
  Future<RateLimitPolicy?> createPolicy() async => null;

  @override
  List<RateLimitCounter> createCounters() => [
    RateLimitCounter(
      name: 'app',
      column: schema.apiKey,
      // Only API keys of real apps get a counter of their own.
      key: (apiKey) async => _apps[apiKey],
      policy: (app) async => switch (app) {
        // No known API key: counted per IP, at a low limit.
        null => const RateLimitPolicy(
          maxRequests: 20,
          window: Duration(minutes: 5),
        ),
        final app when _enterprise.contains(app) => const RateLimitPolicy(
          maxRequests: 10000,
          window: Duration(minutes: 5),
        ),
        _ => const RateLimitPolicy(
          maxRequests: 1000,
          window: Duration(minutes: 5),
        ),
      },
    ),
    RateLimitCounter(
      name: 'device',
      column: schema.installId,
      policy: (_) async =>
          const RateLimitPolicy(maxRequests: 30, window: Duration(minutes: 5)),
    ),
  ];
}

UploadRateLimits main() => UploadRateLimits();
```

Each `POST /db` or `POST /db/many` on `uploads` is now counted against both counters and refused when either one is spent. With 300 devices of one app behind one office IP, each device gets its own 30, and the app as a whole gets its plan's 1000 or 10000, however many addresses its devices use.

| Field | Meaning |
| --- | --- |
| `name` | Names the counter's bucket and is reported in the 429. Lowercase letters, digits and `_`, starting with a letter. Unique within the table. Keep it stable: renaming it starts every key on a fresh counter. |
| `column` | The column of the submitted row whose value keys the counter. |
| `key` | Optional. Maps the row's value to the key it is counted under, or returns `null` when the table doesn't recognise it. Left out, the value itself is the key. |
| `policy` | The policy for one key, or `null` to leave that key unlimited. Called with `null` when the create has no usable key. |

`createCounters()` is read once per table for the life of the server, so return the same counters every time. `key` and `policy` run on every create, in the rate-limit worker, so keep them cheap. The worker is a long-lived process, so a lookup they make can be cached there.

## The Per-IP Counter

`createPolicy()` still defines the per-IP counter, and it is counted alongside the keyed ones. Leaving it at its default of 100 per minute per IP keeps that cap in front of your counters. Return `null`, as above, when one address legitimately sends more than that.

A table that doesn't override `createCounters()` has none, and is limited per IP exactly as before.

## When a Row Has No Key

A create has no key for a counter when the column is missing from the row, empty, `null`, neither a string nor a number, or when `key` returns `null` or an empty string. A `POST /db/many` whose rows don't all have the same value has no key either, so one request can't spread its rows over several counters.

A create with no key isn't let through or refused. It is counted on the caller's IP address, in the counter's own bucket, apart from the per-IP counter, and at the policy that `policy(null)` returns. In the example above, an upload without a known API key gets 20 per 5 minutes per address.

## Callers Who Rotate Keys

The key comes from the row, and the caller writes the row. Without `key`, a caller can send a new value on every request, and each new value starts on a fresh counter.

- **Use `key` for anything that grants a bigger budget.** Map the value to an identity you issued and return `null` for anything else. Made-up values then all land on the same keyless, per-IP counter.
- **Pair a counter whose key is invented with one whose key isn't.** In the example, a caller can make up install ids, but every create still counts against its app's counter, so new device ids never add up to more than the app's budget.
- **The column is fixed by the table.** A caller can't choose a different column, header or value to be counted under.

Counters key on the stored row's value as the client sent it, before any `beforeCreate` extension changes it.

## Storage

Keyed counters share the internal `_rate_limit` table with the per-IP ones, and the `_delete_old_rate_limits` cron job clears them out the same way. No migration is needed. The key is stored as a SHA-256 hash, so the table never holds a raw API key.

## The 429 Response

A create refused by a keyed counter carries the same status, headers and body as any other 429 (see [The 429 Response](/rate-limiting/overview#the-429-response)), with one more field:

```json
{"error":"Rate limit exceeded","collection":"uploads","operation":"create","counter":"device","retryAfter":42}
```

- **`counter`**: the name of the keyed counter that refused the request. It is absent when the per-IP counter refused it.

When more than one counter is spent, the 429 names the one that resets last, so retrying after `Retry-After` gets through. Clients behind one IP no longer share a reset time for keyed counters; each waits for its own.

## Related

- [Configuring Policies](/rate-limiting/configuring-policies)
- [Rate Limiting Overview](/rate-limiting/overview)
- [Trusted Proxies](/rate-limiting/trusted-proxies)
