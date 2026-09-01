# Rate limiting

Zonai rate-limits HTTP requests **per client IP**, **per collection**, and **per operation** (for example `get`, `create`, or `signIn`). When a client exceeds the configured limit within the policy window, the server responds with **429 Too Many Requests**.

Rate limit policies are defined in Dart under your project’s **`rateLimitPath`** (default `lib/src/rate_limit`, overridable in `zonai.yaml`). They are compiled into the `db_rate_limit` worker executable alongside config, rules, extensions, and operations.

## How it works

1. An incoming HTTP request hits a route.
2. The server asks the compiled rate-limit worker which policy applies for that collection and operation.
3. The server tracks usage in the internal `_rate_limit` SQLite table, keyed by client IP, collection name, and operation.
4. If the count for the current window is below `maxRequests`, the request proceeds; otherwise the server returns 429 with `Retry-After` and `X-RateLimit-*` headers naming when the window resets (see [HTTP behavior](#http-behavior)).

Policies are resolved at request time, so you can change limits in Dart and recompile without restarting the database.

## Client IP

Rate limits key on the client IP from Revali’s `@Ip()` / `request.ip`. Behind a reverse proxy (nginx, Coolify, Cloudflare, Fly.io, etc.), the TCP peer is usually the proxy — not the browser — so you must configure **trusted proxy headers**.

In your config worker (`lib/src/config/db_config*.dart`), set `AppConfig.trustedProxy`:

```dart in:project-file
AppConfig main() {
  return AppConfig(
    appName: 'My App',
    passwordSecret: '...',
    jwtSecret: '...',
    trustedProxy: const TrustedProxyConfig(
      headers: ['X-Forwarded-For', 'X-Real-IP', 'CF-Connecting-IP'],
      // useLeftmostIp: false, // default — rightmost IP (recommended)
    ),
  );
}
```

At server startup, the HTTP app loads this config and passes it to [Revali Router’s `TrustedProxy`](https://github.com/mrgnhnt96/revali/tree/main/revali_router/revali_router). Resolution rules:

| Setting | Behavior |
| ------- | -------- |
| `headers` empty | Use TCP remote address only (local dev, no proxy). |
| `useLeftmostIp: false` (default) | **Rightmost** valid IP in each comma-separated header value — the one your trusted proxy appended. |
| `useLeftmostIp: true` | **Leftmost** valid IP — only when you understand the spoofing risk. |

List headers in the order your deployment uses; the first header that yields a valid IP wins. Put your proxy’s primary header first (for example `CF-Connecting-IP` on Cloudflare, `X-Forwarded-For` behind nginx).

See also **[server-binding.md](server-binding.md)** for binding behind Docker and reverse proxies.

## Project layout

Default directory (override with `rateLimitPath` in `zonai.yaml`):

```text
lib/src/rate_limit/
  item_rate_limits.dart
  user_rate_limits.dart
```

Each `.dart` file must export a `main()` that returns a `RateLimits` instance for one collection:

```dart
import 'package:my_app/src/schemas/items.dart';
import 'package:zonai_schema/src/rate_limits/table/rate_limits.dart';
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

ItemRateLimits main() => ItemRateLimits();

final class ItemRateLimits extends TableRateLimits<ItemTable, Item> {
  ItemRateLimits() : super(items);

  @override
  Future<RateLimitPolicy?> getPolicy() async {
    return const RateLimitPolicy(
      maxRequests: 100,
      window: Duration(minutes: 1),
    );
  }
}
```

Only files with a `.dart` extension under `rateLimitPath` are compiled. If the directory is missing or empty, the worker still compiles with built-in defaults only.

## Base classes

| Table type    | Extend                           | Example                      |
| ------------------ | -------------------------------- | ---------------------------- |
| Regular collection | `TableRateLimits<S, R>`     | Items, posts, companies      |
| Auth collection    | `AuthTableRateLimits<S, R>` | Users with sign-in / sign-up |

Define **one rate-limit file per collection**. If multiple files target the same table, the last one loaded wins for each base class (`TableRateLimits` vs `AuthTableRateLimits`).

## Policy methods

Override the methods that correspond to the operations you want to customize. Each base-class method returns `RateLimitPolicy.defaultPolicy` (**100 requests per minute**). Return a different `RateLimitPolicy` to tighten or loosen a limit, or return **`null`** to disable limiting for that operation.

### Data operations (`TableRateLimits`)

| Operation | Policy method    | Used by                         |
| --------- | ---------------- | ------------------------------- |
| `get`     | `getPolicy()`    | `GET /db`, stream-one           |
| `list`    | `limitPolicy()`  | `GET /db/list`, stream-list     |
| `count`   | `countPolicy()`  | `GET /db/count`                 |
| `create`  | `createPolicy()` | `POST /db`, `POST /db/many`     |
| `update`  | `updatePolicy()` | `PATCH /db`, `PATCH /db/many`   |
| `delete`  | `deletePolicy()` | `DELETE /db`, `DELETE /db/many` |

### Custom operations (`TableOperations.custom`)

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

`PATCH /db/custom/:operation` buckets separately per operation name (`fill` and `reserve` on the same collection get independent counters), but only for a name that's registered in that collection's `TableRules.customOperations` — an unrecognized operation name is rejected with **404** before it ever reaches the rate limiter, so it can't be used to dodge a limit by rotating the name.

Checking that registration means reading the collection's rules, which the server can only do without an IPC round-trip when rules are linked into the binary. When they aren't — a binary built without a project link, or `ZONAI_FORCE_WORKERS=1` — the name arrives unvalidated, and bucketing on it would restore exactly the bypass above. The server drops the name instead of the limit: `operation` is **`null`**, every custom operation on the collection shares one counter, and the `404` is skipped (the rules layer still denies an unregistered operation, just later in the request). Handle `null` if that shared counter should differ from `defaultPolicy`.

### Auth operations (`AuthTableRateLimits`)

| Operation           | Policy method               | Used by                     |
| ------------------- | --------------------------- | --------------------------- |
| `authenticate`      | `authenticatePolicy()`      | `POST /auth`                |
| `signIn`            | `signInPolicy()`            | `POST /auth/sign-in`        |
| `refreshToken`      | `refreshTokenPolicy()`      | `POST /auth/refresh`        |
| `signUp`            | `signUpPolicy()`            | `POST /auth/sign-up`        |
| `sendResetPassword` | `sendResetPasswordPolicy()` | `POST /auth/reset-password` |
| `sendVerifyEmail`   | `sendVerifyEmailPolicy()`   | `POST /auth/verify-email`   |
| `sendOtp`           | `sendOtpPolicy()`           | OTP flows                   |
| `sendMagicLink`     | `sendMagicLinkPolicy()`     | Magic-link flows            |
| `confirm`           | `confirmPolicy()`           | Confirm / verify            |
| `logout`            | `logoutPolicy()`            | Logout                      |
| `logoutAll`         | `logoutAllPolicy()`         | Logout all sessions         |
| `adminAuthenticate` | `adminAuthenticatePolicy()` | Admin auth                  |
| `adminSignIn`       | `adminSignInPolicy()`       | Admin sign-in               |

Not every auth route is guarded today (for example `POST /auth/confirm` and `POST /auth/admin` have no rate-limit guard). Override a policy method only when the corresponding endpoint is rate-limited.

## `RateLimitPolicy`

```dart in:expression
const RateLimitPolicy(
  maxRequests: 10,               // allowed requests per window
  window: Duration(minutes: 15), // fixed window length
),
```

- **`maxRequests`** — maximum number of requests allowed from one IP for this collection + operation within one window.
- **`window`** — the length of one window.

The window is **fixed** (it does not slide). It starts at the first counted request from that IP for that collection + operation, and it resets on the first request after `window` has elapsed since it started — that request opens a new window and counts as its first. Requests refused with 429 are **not** counted and do **not** extend the window, so a client that keeps retrying is told the same reset instant every time and cannot push it further away. With `maxRequests: 10, window: 15 minutes`, ten requests at 12:00 exhaust the window and the eleventh is refused until 12:15 no matter how many refusals happen in between.

Return **`null`** from an override to allow unlimited requests for that operation.

## Defaults

Every policy method on `TableRateLimits` and `AuthTableRateLimits` returns `RateLimitPolicy.defaultPolicy` (**100 requests per minute**) unless you override it.

| Situation                                 | Behavior                                                                                                                                                   |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **No rate-limit file** for the collection | Framework defaults apply: **100 requests per minute** for every operation.                                                                                 |
| **Rate-limit file exists**                | Non-overridden methods inherit the base-class default. Override a method to customize it, or return `null` to allow unlimited requests for that operation. |

Example: if `ItemRateLimits` overrides only `getPolicy`, `limitPolicy`, and `countPolicy`, then `create`, `update`, and `delete` for `items` still use the base-class default of 100 requests per minute.

## Auth collection example

From `apps/playground/lib/src/rate_limit/user_rate_limits.dart`:

```dart in:project-file
final class UserRateLimits
    extends AuthTableRateLimits<UserTable, User> {
  UserRateLimits() : super(users);

  @override
  Future<RateLimitPolicy?> signInPolicy() async {
    return const RateLimitPolicy(
      maxRequests: 10,
      window: Duration(minutes: 15),
    );
  }

  @override
  Future<RateLimitPolicy?> signUpPolicy() async {
    return const RateLimitPolicy(maxRequests: 5, window: Duration(hours: 1));
  }
}
```

Sign-in is capped at 10 requests per 15 minutes per IP; sign-up at 5 per hour. Other auth operations on `users` use the base-class default (100 per minute) unless you override their policy methods or return `null` to disable limiting.

## Commands

From your app directory (where `zonai.yaml` lives):

```bash
# Compile all workers, including rate limits
dart run zonai compile

# Dev server: watches rateLimitPath and recompiles on change
dart run zonai serve
```

While `serve` is running, press **`c`** to recompile all workers (config, rules, extensions, operations, rate limits, crons).

The compiled executable is written to `.zonai/executables/db_rate_limit.exe` (path configurable via the zonai data directory).

## Configuration

`zonai.yaml`:

```yaml
rateLimitPath: lib/src/rate_limit
```

## Internal storage

Request counts are stored in the framework-managed `_rate_limit` table. You do not add schema or migration files for it. Admin users can delete rate-limit records through the normal rules for that internal collection; ordinary clients cannot read or modify them.

## HTTP behavior

When a client exceeds a limit, the guard returns **`429 Too Many Requests`** with headers that say exactly when to come back:

| Header                  | Value                                                                                                          |
| ----------------------- | -------------------------------------------------------------------------------------------------------------- |
| `Retry-After`           | Whole seconds until the window resets, rounded **up** and never `0` (so a client never retries into the same closed window). |
| `X-RateLimit-Limit`     | The policy's `maxRequests`.                                                                                    |
| `X-RateLimit-Remaining` | `0` — the request was refused.                                                                                 |
| `X-RateLimit-Reset`     | The instant the window resets, as a Unix epoch in whole seconds (UTC).                                         |

The body is JSON and names the policy that was hit, so a client throttled on `create` can keep reading, and a human can see which limit to raise:

```json
{
  "error": "Rate limit exceeded",
  "collection": "items",
  "operation": "create",
  "retryAfter": 42
}
```

- **`collection`** — the collection the request targeted, or a framework bucket for routes that carry no collection (`__admin_auth__` for admin sign-in and reset, `__auth_confirm__` for `POST /auth/confirm`, `oauth` for OAuth callbacks, `oauth_admin` and `oauth_admin_invite` for the admin OAuth start routes).
- **`operation`** — the `RateLimitOperation` name (`get`, `create`, `signIn`, `custom`, ...).
- **`customOperation`** — present only for `PATCH /db/custom/:operation` when the name was validated; the name of the custom operation whose counter was hit.
- **`retryAfter`** — the same number as the `Retry-After` header.

A full refusal looks like:

```http
HTTP/1.1 429 Too Many Requests
retry-after: 42
x-ratelimit-limit: 100
x-ratelimit-remaining: 0
x-ratelimit-reset: 1788307242
content-type: application/json

{"error":"Rate limit exceeded","collection":"items","operation":"create","retryAfter":42}
```

Wait `Retry-After` seconds and retry once. Because the window is fixed and refusals do not extend it, the reset instant is the same for every client behind one IP; several agents sharing an address should all wait for `X-RateLimit-Reset` rather than each retrying on its own schedule.

The rate-limit headers are sent on the 429 only; successful responses do not carry them today.

**Through 0.9.0 the body was the plain string `Rate limit exceeded`.** A client that matched on that text should key on the `429` status code instead (or on the `error` field of the JSON body, which carries the same string).

`PATCH /db/custom/:operation` additionally returns **404 Not Found** when `:operation` isn't registered in that collection's `TableRules.customOperations` (see [rules.md](rules.md#custom-operation-rules)) — checked before the rate limiter, not after.

## Write backpressure (503)

Rate limiting is per IP and per policy. Separately from it, the server bounds how much write work it will hold at once, and that bound is global: mutating requests (create, update, delete, and the write half of sign-up) run on a single-writer queue so concurrent writes do not pile into SQLite's busy timeout. The queue holds **64** pending writes. A write that arrives when 64 are already waiting is refused before any work is done, with **`503 Service Unavailable`**, the body `{"error": "Server is busy writing; retry shortly (write queue saturated)."}`, and:

| Header        | Value                                                                 |
| ------------- | --------------------------------------------------------------------- |
| `Retry-After` | `1`. Whole seconds, from a single constant (`kBackpressureRetryAfterSeconds`). |

The value is a **floor, not a prediction**. The queue drains in tens of milliseconds and the server does not know when a slot will free, so it does not guess; `1` is the smallest delay HTTP can express, and the point of sending it is that a client stops retrying blind. Refusing is cheap for the server, so what keeps a saturated queue saturated is the caller: `stress/README.md` measures ~98% of writes refused at concurrency 100, and records that making rejection cheaper let its backoff-free load generator land *more* attempts in the same window rather than fewer. Wait at least `Retry-After` seconds and retry; a client that had several writes refused should retry them in sequence rather than re-issuing the whole burst at once, since the burst is what filled the queue.

No `X-RateLimit-*` headers are sent on this 503: there is no per-client window to describe. A 429 says *you* have been asking too often; this 503 says the server is busy, whoever is asking.

## See also

- **[server-binding.md](server-binding.md)** — host/port and reverse-proxy deployment
- **[config-and-env-flavors.md](config-and-env-flavors.md)** — `trustedProxy` on `AppConfig`
- **[auth.md](auth.md)** — session tokens and the refresh endpoint
- **[extensions.md](extensions.md)** — lifecycle hooks around mutations and auth
- **[rules.md](rules.md)** — authorization (checked before rate limits on data routes)
- **[cron.md](cron.md)** — scheduled background jobs
