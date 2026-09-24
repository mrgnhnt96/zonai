---
title: Auth Rate Limits
description: Setting rate limits on authentication endpoints.
---

Auth endpoints are common brute-force and email-flooding targets. The default 100 requests per minute is often too permissive for sign-in and password-reset flows.

## AuthTableRateLimits

Extend `AuthTableRateLimits<S, R>` in the auth table's rate limits file. Pass the schema ref to `super()`:

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserRateLimits extends AuthTableRateLimits<UserTable, User> {
  UserRateLimits() : super(users);

  @override
  Future<RateLimitPolicy?> authenticatePolicy() async =>
      const RateLimitPolicy(maxRequests: 10, window: Duration(minutes: 15));

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

`AuthTableRateLimits` only covers the auth routes. `/db` reads and writes on the same table are limited by a `TableRateLimits` for that table (a separate class, in its own file), or by the default if there is none.

## Methods That Apply Per Table

These are looked up on the auth table the request names, so your override takes effect:

| Method | Endpoint | Default | Suggested |
|--------|----------|---------|-----------|
| `authenticatePolicy()` | `POST /auth` (password sign-in/up, send OTP, send magic link) and `POST /auth/oauth` | 100/min | 10/15min |
| `signInPolicy()` | `POST /auth/sign-in` | 100/min | 10/15min |
| `signUpPolicy()` | `POST /auth/sign-up` | 100/min | 5/hour |
| `sendResetPasswordPolicy()` | `POST /auth/reset-password` | 100/min | 5/hour |
| `sendVerifyEmailPolicy()` | `POST /auth/verify-email` | 100/min | 5/hour |
| `oauthStartPolicy()` | `GET /auth/oauth/start/:provider?table=` | 100/min | default |
| `adminInvitePolicy()` | `POST /admin/invites` (bucketed on the inviting admin's table) | 100/min | default |
| `externalIdpProvisioningPolicy()` | First sight of an external-IdP user; see [External Identity Providers](/authentication/external-idp#first-seen-provisioning-is-rate-limited) | 30/hour | default |

All methods are `async` and return `Future<RateLimitPolicy?>`. Return `null` to disable rate limiting for that endpoint.

**OTP and magic-link sends go through `authenticatePolicy()`.** `POST /auth` handles password sign-in and sign-up as well as sending OTP codes and magic links, and every request to it counts against one policy. Tightening it for OTP tightens it for password sign-in on that route too.

## Methods That Are Never Consulted

`AuthTableRateLimits` also declares these methods, but overriding them has no effect. Either no route checks them, or the route's counter is not tied to a table (see below):

| Method | Why | What actually applies |
|--------|-----|-----------------------|
| `sendOtpPolicy()`, `sendMagicLinkPolicy()` | Sends go through `POST /auth` | `authenticatePolicy()` |
| `logoutPolicy()`, `logoutAllPolicy()` | `DELETE /auth` and `DELETE /auth/all` are not rate limited | nothing |
| `adminSignInPolicy()` | No route checks it | — |
| `adminAuthenticatePolicy()` | `POST /auth/admin` shares one counter across all tables | fixed 10/15min per IP |
| `confirmPolicy()` | `POST /auth/confirm` shares one counter across all tables | fixed 100/min per IP |
| `refreshTokenPolicy()` | `POST /auth/refresh` shares one counter across all tables | fixed 100/min per IP |

## Endpoints That Carry No Table

Some endpoints are counted per IP under a shared, synthetic key instead of per auth table, because the request does not name a trustworthy table:

| Endpoint | Bucket (`collection` in the 429 body) | Limit |
|----------|---------------------------------------|-------|
| `POST /auth/confirm` (the body is a token, or an email and a code) | `__auth_confirm__` | 100/min |
| `POST /auth/refresh` (the token's table claim is not verified yet) | `__auth_header__` | 100/min |
| `POST /auth/admin` (the admin table is resolved on the server) | `__admin_auth__` | 10/15min |
| `POST /auth/reset-password` for an admin | `__admin_auth__` | 100/min |
| `GET`/`POST /auth/oauth/callback/:provider` | `oauth` | 60/min |
| `GET /auth/admin/oauth/start/:provider` | `oauth_admin` | 100/min |
| Admin invite OAuth routes (`/auth/admin/invite*`) | `oauth_admin_invite` | 100/min |

A per-table override does not apply to any of these. There is no table to match it against, so the framework limit is what runs.

<Info>

`POST /auth/confirm` is worth knowing about even though it takes no password: every attempt reaches an Argon2 verification, which is expensive by design. That cost is the server's, not the caller's, so the limit here is about CPU exhaustion rather than about guessing — the tokens it checks are 32 bytes from a secure random source and are not guessable.

</Info>

## One Email Per Address Per Minute

Separately from the per-IP policies, the endpoints that send a code or link refuse a second send **to the same address** within one minute. This applies to OTP codes, magic links, password resets, verification emails and admin invites. The refusal is a `429` with the body `{"error": "Must wait 60 seconds before sending a new code"}` and no `Retry-After` or `X-RateLimit-*` headers. It cannot be configured.

<Info>

Email-sending endpoints (`authenticatePolicy` for OTP and magic link, `sendResetPasswordPolicy`, `sendVerifyEmailPolicy`) should still be throttled aggressively. The per-address check stops one inbox being flooded. It does not stop an attacker sending one email each to many addresses through your SMTP account.

</Info>
