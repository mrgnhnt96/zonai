---
title: Magic Link Auth
description: Passwordless authentication via a single-use emailed link.
---

Magic link authentication lets users sign in by clicking a link sent to their email address. No password or code entry required.

## Enabling Magic Link Auth

Add `with MagicLinkAuth` to your auth table class. No additional columns are needed — magic link tokens are transient:

```dart no-analyze
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
  "email": "alice@example.com",
  "metadata": { "name": "Alice" }
}
```

Returns `200 OK` with an empty body. Zonai generates a single-use secret, stores only its hash, and emails a link via the `magic_link` template. The optional `metadata` object becomes the new row's extra fields if this turns out to be a sign-up — there is no separate sign-up call: if no account exists for the email and `canSignUp` allows it, following the link creates one.

One link per address per minute: a second request inside the minute answers `429`. Requesting a new link invalidates the previous one.

**Step 2 — Your page exchanges the link for a session.** The emailed link is:

```
{baseUrl}{path}?s=<secret>
```

`path` comes from `AuthOperations.magicLinkConfig()` and defaults to `/auth/magic-link`. It may also be a full URL when your frontend lives on a different origin from `AppConfig.baseUrl`. There is **no server-side redirect and no token in the URL** — whatever serves that URL (your frontend, or your app via a deep link) reads `s` and posts it back:

```
POST /auth/confirm
```

```json
{
  "type": "verifyMagicLink",
  "secret": "<the s query parameter>"
}
```

On success: `canSignIn` (or `canSignUp` for a new account) in auth row rules is evaluated, `onSignIn` (or `onSignUp`) fires, and the response includes the user row and `accessToken` — also delivered in the `X-Auth` header.

## Single-Use Guarantee

Each link works exactly once. A successful exchange consumes it, and a wrong secret uses up its one attempt. Expired or already-used links return `401` — the user requests a new one.

## Configuration

Override `magicLinkConfig()` in your `AuthOperations` class to change `path` and `expiresIn` (default **10 minutes**) — see [Auth Operations](/operations/auth-operations). Magic link sign-in is unaffected by a [forced password reset](/authentication/password-auth#forced-password-reset).
