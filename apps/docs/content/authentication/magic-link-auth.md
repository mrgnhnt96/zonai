---
title: Magic Link Auth
description: Passwordless authentication via a single-use emailed link.
---

Magic link authentication lets users sign in by clicking a link sent to their email address. No password or code entry required.

## Enabling Magic Link Auth

Add `with MagicLinkAuth` to your auth table class. No additional columns are needed — magic link tokens are transient:

```dart
final class UserTable extends AuthTable<User>
    with MagicLinkAuth {
  // or with other auth methods:
  // with PasswordAuth, MagicLinkAuth
}

final users = authTable('users', UserTable.new);
```

## The Magic Link Flow

**Step 1 — Request the link:**

```
POST /auth
```

```json
{
  "type": "sendMagicLink",
  "table": "users",
  "email": "alice@example.com"
}
```

Returns `200 OK` with an empty body. Zonai generates a single-use token and sends it via the `magic_link` email template. If the account doesn't exist and your auth rules allow sign-up, the account may be created automatically.

**Step 2 — Automatic handling via redirect:**

When the user clicks the link in their email, Zonai validates the token and redirects to the URL configured in `AuthOperations.magicLinkConfig()`. The JWT is passed to the client via that redirect — typically as a query parameter:

```
https://myapp.com/auth/callback?token=eyJ...
```

The client stores the token and uses it for subsequent requests.

**Handling the link manually:**

If you prefer to handle the link in your own frontend rather than relying on a redirect, you can exchange the token directly:

```
POST /auth/confirm
```

```json
{
  "type": "verifyMagicLink",
  "secret": "abc123..."
}
```

On success: `canSignIn` in auth row rules is evaluated, `onSignIn` fires, and the response includes the user row and `accessToken`.

## Single-Use Guarantee

Each magic link token is valid for exactly one use. After the link is clicked (successfully or not), the token is immediately invalidated. Expired or already-used tokens return `401`.

## Configuration

Link expiry time and the redirect URL are configured via `AuthOperations.magicLinkConfig()` — see [Auth Operations](/operations/auth-operations).
