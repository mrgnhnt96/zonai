---
title: Session Management
description: Refreshing tokens, revoking sessions, and configuring JWT lifetime.
---

## Token Lifetime

By default, tokens expire 14 days after they are issued. This is set globally in `AppConfig`:

```dart
AppConfig(
  jwtExpiresIn: const Duration(days: 14),
  // ...
)
```

To override the lifetime for a specific auth table, set `jwtExpiresIn` in that table's `AuthOperations` class — see [Auth Operations](/operations/auth-operations).

After a token expires, any request using it returns `401 Unauthorized`. The user must sign in again or have refreshed their token before it expired.

## Refreshing a Token

```
POST /auth/refresh
Authorization: Bearer <current-token>
```

No request body. Zonai validates the current token, revokes it, issues a new token with a fresh expiry window, and returns it:

```json
{
  "data": {
    "accessToken": "eyJ...",
    "user": { "id": "abc_us", ... }
  }
}
```

The `onRefresh` extension hook fires after the new token is issued.

Refresh the token proactively — before it expires. A common pattern is to check the token's `expiresAt` claim on each app launch and refresh if it will expire within the next 24 hours.

<Info>
You can only refresh a token that is still valid. Once a token expires, the user must sign in again from scratch.
</Info>

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

Revokes every active token for this user across all devices and sessions. Useful for a "sign out everywhere" feature or after a password change. The `onLogout` extension hook fires once per revoked token.

## The _jwt Table

Zonai maintains an internal `_jwt` table that tracks which tokens are active and which have been revoked. Token verification checks this table, so revocations take effect immediately — there is no delay waiting for the token to expire.

Old entries are cleaned up automatically by built-in cron jobs.
