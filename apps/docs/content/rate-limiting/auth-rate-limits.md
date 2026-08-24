---
title: Auth Rate Limits
description: Setting rate limits on authentication endpoints.
---

Auth endpoints are common brute-force and email-flooding targets. The default 100 req/min is often too permissive for sign-in and password-reset flows.

## AuthTableRateLimits

Extend `AuthTableRateLimits<S, R>` in the auth table's rate limits file. Pass the schema ref to `super()`:

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserRateLimits extends AuthTableRateLimits<UserTable, User> {
  UserRateLimits() : super(users);

  @override
  Future<RateLimitPolicy?> signInPolicy() async =>
      const RateLimitPolicy(maxRequests: 10, window: Duration(minutes: 15));

  @override
  Future<RateLimitPolicy?> signUpPolicy() async =>
      const RateLimitPolicy(maxRequests: 5, window: Duration(hours: 1));

  @override
  Future<RateLimitPolicy?> sendResetPasswordPolicy() async =>
      const RateLimitPolicy(maxRequests: 5, window: Duration(hours: 1));
}

UserRateLimits main() => UserRateLimits();
```

## Available Methods

| Method | Endpoint | Recommended Limit |
|--------|----------|-------------------|
| `signUpPolicy()` | `POST /auth/sign-up` | 5/hour |
| `signInPolicy()` | `POST /auth/sign-in` | 10/15min |
| `authenticatePolicy()` | `POST /auth` (confirm) | 20/15min |
| `confirmPolicy()` | `POST /auth/confirm` | framework default — see below |
| `refreshTokenPolicy()` | `POST /auth/refresh` | default |
| `logoutPolicy()` | `DELETE /auth` | default |
| `logoutAllPolicy()` | `DELETE /auth/all` | default |
| `sendResetPasswordPolicy()` | `POST /auth/reset-password` | 5/hour |
| `sendVerifyEmailPolicy()` | `POST /auth/verify-email` | 5/hour |
| `sendOtpPolicy()` | `POST /auth` (sendOtp) | 5/15min |
| `sendMagicLinkPolicy()` | `POST /auth` (sendMagicLink) | 5/15min |
| `adminSignInPolicy()` | `POST /auth/admin` | 10/15min |
| `adminAuthenticatePolicy()` | Admin auth confirm | 10/15min |

All methods are `async` and return `Future<RateLimitPolicy?>`. Return `null` to disable rate limiting for that endpoint.

## Endpoints that carry no collection

Two endpoints are bucketed per-IP on a shared, synthetic key rather than per auth table, because their request body does not name one: `POST /auth/confirm` (the body is a token, or an email and a code) and the admin auth endpoints (the admin table is resolved server-side from config).

For those, **a per-table override does not apply** — there is no table to match it against, so the framework default is what runs. `POST /auth/confirm` is limited at the generic 100/min per IP; admin auth is limited far below that, at 10/15min.

<Info>

`POST /auth/confirm` is worth knowing about even though it takes no password: every attempt reaches an Argon2 verification, which is expensive by design. That cost is the server's, not the caller's, so the limit here is about CPU exhaustion rather than about guessing — the tokens it checks are 32 bytes from a secure random source and are not guessable.

</Info>

<Info>

Email-sending endpoints (`sendOtpPolicy`, `sendMagicLinkPolicy`, `sendResetPasswordPolicy`, `sendVerifyEmailPolicy`) should be throttled aggressively. Unconstrained, an attacker can use your SMTP account to flood anyone's inbox.

</Info>
