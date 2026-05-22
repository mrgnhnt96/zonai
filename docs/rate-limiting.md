# Rate limiting

Zonai rate-limits HTTP requests **per client IP**, **per collection**, and **per operation** (for example `get`, `create`, or `signIn`). When a client exceeds the configured limit within the policy window, the server responds with **429 Too Many Requests**.

Rate limit policies are defined in Dart under your project’s **`rateLimitPath`** (default `lib/src/rate_limit`, overridable in `zonai.yaml`). They are compiled into the `db_rate_limit` worker executable alongside config, rules, extensions, and operations.

## How it works

1. An incoming HTTP request hits a route.
2. The server asks the compiled rate-limit worker which policy applies for that collection and operation.
3. The server tracks usage in the internal `_rate_limit` SQLite table, keyed by client IP, collection name, and operation.
4. If the count for the current window is below `maxRequests`, the request proceeds; otherwise the server returns 429.

Policies are resolved at request time, so you can change limits in Dart and recompile without restarting the database.

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
import 'package:zonai_schema/src/rate_limits/collection/rate_limits.dart';
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

ItemRateLimits main() => ItemRateLimits();

final class ItemRateLimits extends CollectionRateLimits<ItemCollection, Item> {
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

| Collection type    | Extend                           | Example                      |
| ------------------ | -------------------------------- | ---------------------------- |
| Regular collection | `CollectionRateLimits<S, R>`     | Items, posts, companies      |
| Auth collection    | `AuthCollectionRateLimits<S, R>` | Users with sign-in / sign-up |

Define **one rate-limit file per collection**. If multiple files target the same table, the last one loaded wins for each base class (`CollectionRateLimits` vs `AuthCollectionRateLimits`).

## Policy methods

Override the methods that correspond to the operations you want to customize. Each base-class method returns `RateLimitPolicy.defaultPolicy` (**100 requests per minute**). Return a different `RateLimitPolicy` to tighten or loosen a limit, or return **`null`** to disable limiting for that operation.

### Data operations (`CollectionRateLimits`)

| Operation | Policy method    | Used by                         |
| --------- | ---------------- | ------------------------------- |
| `get`     | `getPolicy()`    | `GET /db`, stream-one           |
| `list`    | `limitPolicy()`  | `GET /db/list`, stream-list     |
| `count`   | `countPolicy()`  | `GET /db/count`                 |
| `create`  | `createPolicy()` | `POST /db`                      |
| `update`  | `updatePolicy()` | `PATCH /db`, `PATCH /db/many`   |
| `delete`  | `deletePolicy()` | `DELETE /db`, `DELETE /db/many` |

### Auth operations (`AuthCollectionRateLimits`)

| Operation           | Policy method               | Used by                     |
| ------------------- | --------------------------- | --------------------------- |
| `authenticate`      | `authenticatePolicy()`      | `POST /auth`                |
| `signIn`            | `signInPolicy()`            | `POST /auth/sign-in`        |
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

```dart
const RateLimitPolicy(
  maxRequests: 10,              // allowed requests per window
  window: Duration(minutes: 15), // sliding window length
);
```

- **`maxRequests`** — maximum number of requests allowed from one IP for this collection + operation within one window.
- **`window`** — after this duration elapses since the first request in a window, the counter resets.

Return **`null`** from an override to allow unlimited requests for that operation.

## Defaults

Every policy method on `CollectionRateLimits` and `AuthCollectionRateLimits` returns `RateLimitPolicy.defaultPolicy` (**100 requests per minute**) unless you override it.

| Situation                                 | Behavior                                                                                                                                                   |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **No rate-limit file** for the collection | Framework defaults apply: **100 requests per minute** for every operation.                                                                                 |
| **Rate-limit file exists**                | Non-overridden methods inherit the base-class default. Override a method to customize it, or return `null` to allow unlimited requests for that operation. |

Example: if `ItemRateLimits` overrides only `getPolicy`, `limitPolicy`, and `countPolicy`, then `create`, `update`, and `delete` for `items` still use the base-class default of 100 requests per minute.

## Auth collection example

From `apps/playground/lib/src/rate_limit/user_rate_limits.dart`:

```dart
final class UserRateLimits
    extends AuthCollectionRateLimits<UserCollection, User> {
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

While `serve` is running, press **`c`** to recompile all workers (config, rules, extensions, operations, rate limits).

The compiled executable is written to `.zonai/executables/db_rate_limit.exe` (path configurable via the zonai data directory).

## Configuration

`zonai.yaml`:

```yaml
rateLimitPath: lib/src/rate_limit
```

## Internal storage

Request counts are stored in the framework-managed `_rate_limit` table. You do not add schema or migration files for it. Admin users can delete rate-limit records through the normal rules for that internal collection; ordinary clients cannot read or modify them.

## HTTP behavior

When a client exceeds a limit, the guard returns:

- **Status:** `429 Too Many Requests`
- **Body:** `Rate limit exceeded`

There is no `Retry-After` header today. Clients should back off until the policy window expires.
