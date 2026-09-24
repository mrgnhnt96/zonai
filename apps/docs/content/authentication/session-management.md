---
title: Session Management
description: Refreshing tokens, revoking sessions, and configuring JWT lifetime.
---

## Token Lifetime

By default, tokens expire 24 hours after they are issued. This is set globally in `AppConfig`:

```dart in:app-config
jwtExpiresIn: const Duration(hours: 24),
```

To override the lifetime for a specific auth table, override the `jwtExpiresIn` getter in that table's `AuthOperations` class — see [Auth Operations](/operations/auth-operations).

After a token expires, any request using it returns `401 Unauthorized`. The user must sign in again or have refreshed their token before it expired.

## Refreshing a Token

```
POST /auth/refresh
Authorization: Bearer <current-token>
```

No request body. Zonai validates the current token, reloads the user row, issues a new token with a fresh expiry window (and fresh claims from `addClaims`), **revokes the token it was given**, and returns the new one:

```json
{
  "data": {
    "accessToken": "eyJ...",
    "user": { "id": "abc_us", ... }
  }
}
```

The `onRefresh` extension hook fires for the new session. Refresh does not re-check a password or code — it only requires a valid, non-revoked token.

After a successful refresh the **old** token is rejected everywhere, including for a second refresh. Always replace the stored token with the new one; the [Dart client](/dart-client/authentication) does this for you.

Refresh the token proactively — before it expires. A common pattern is to read the token's `exp` claim on each app launch and refresh if it will expire soon. If refresh fails (expired, revoked, or the user was deleted), treat the session as ended and send the user through sign-in again.

<Info>

You can only refresh a token that is still valid. Once a token expires, the user must sign in again from scratch.

</Info>

`POST /auth/refresh` is rate-limited per client IP by the auth table's `refreshTokenPolicy()` — 100 requests per minute by default. See [Auth Rate Limits](/rate-limiting/auth-rate-limits).

## Logout (Current Session)

```
DELETE /auth
Authorization: Bearer <current-token>
```

Revokes the current token. Subsequent requests with this token return `401`. The `onLogout` extension hook fires.

## Logout (All Sessions)

```
DELETE /auth/all
Authorization: Bearer <current-token>
```

Revokes every active token for this user across all devices and sessions. Useful for a "sign out everywhere" feature. The `onLogout` hook does **not** fire for this call.

Zonai revokes all of an account's sessions on its own in three other places: a completed password reset, an operator [requiring a password reset](/authentication/password-auth#forced-password-reset), and removing an admin.

## The _jwt Table

Zonai maintains an internal `_jwt` table of live sessions. Every request checks it, so revocations take effect immediately — there is no delay waiting for the token to expire. Purging `_jwt` from the dashboard's Maintenance screen signs out every user at once.

Old entries are cleaned up automatically by built-in cron jobs.

Tokens from an [external identity provider](/authentication/external-idp) are not Zonai sessions: they are never in `_jwt`, cannot be refreshed or logged out here, and live until the provider's own expiry.
