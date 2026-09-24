---
title: OTP Auth
description: One-time passcode authentication via email.
---

OTP (one-time passcode) authentication lets users sign in by entering a short numeric code sent to their email address. No password is stored or required.

## Enabling OTP Auth

Add `with OtpAuth` to your auth table class. No additional columns are added — OTP codes are transient and not persisted to the schema:

```dart no-analyze
final class UserTable extends AuthTable<User>
    with OtpAuth {
  // or combined with PasswordAuth:
  // with PasswordAuth, OtpAuth
}

final users = authTable('users', UserTable.new);
```

## The OTP Flow

**Step 1 — Request a code:**

```
POST /auth
```

```json
{
  "type": "sendOtp",
  "table": "users",
  "email": "alice@example.com",
  "metadata": { "name": "Alice" }
}
```

Returns `200 OK` with an empty body. Zonai generates a 6-digit code, stores only its hash, and sends it via the `otp_code` email template. The optional `metadata` object is kept with the code and becomes the new row's extra fields if this turns out to be a sign-up.

There is no separate sign-up call: if no account exists for the email and `canSignUp` allows it, verifying the code creates one. `beforeSignUp` runs both here and again at verify — see [Declining a sign-up](/authentication/password-auth#declining-a-sign-up).

One code per address per minute: a second request inside the minute answers `429`. Requesting a new code invalidates the previous one.

**Step 2 — Verify the code:**

```
POST /auth/confirm
```

```json
{
  "type": "verifyOtp",
  "email": "alice@example.com",
  "code": "123456"
}
```

On a valid code: `canSignIn` (or `canSignUp` for a new account) in auth row rules is evaluated, the `onSignIn` (or `onSignUp`) extension fires, and the response includes the user row and an `accessToken`.

On an invalid or expired code: `401 Unauthorized`.

<Info>

A code is valid for **10 minutes** and allows **3** verification attempts; after that the user must request a new one. Both values are fixed — there is no per-table configuration for them. Sending a code goes through `POST /auth`, so it is throttled by `authenticatePolicy()` (the declared `sendOtpPolicy()` is never consulted), plus a fixed one-send-per-address-per-minute limit. See [Auth Rate Limits](/rate-limiting/auth-rate-limits).

</Info>

## Using OTP Alongside Password Auth

A table can use both `PasswordAuth` and `OtpAuth` at the same time:

```dart no-analyze
final class UserTable extends AuthTable<User>
    with PasswordAuth, OtpAuth {
  // ...
}
```

Users can sign in via either method — both lead to the same account and the same kind of session. OTP is an *alternative* way in, not a second factor on top of the password. OTP sign-in is also unaffected by a [forced password reset](/authentication/password-auth#forced-password-reset).
