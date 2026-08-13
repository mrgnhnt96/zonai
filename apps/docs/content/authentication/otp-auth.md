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
  "email": "alice@example.com"
}
```

Returns `200 OK` with an empty body. Zonai generates a short numeric code, stores it temporarily, and sends it via the `otp_code` email template. If the account doesn't exist and your auth rules allow sign-up, the account may be created automatically.

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

On a valid code: `canSignIn` in auth row rules is evaluated, the `onSignIn` extension fires, and the response includes the user row and an `accessToken`.

On an invalid or expired code: `401 Unauthorized`.

<Info>

After 3 failed verification attempts, the code is invalidated. The user must request a new code via `POST /auth`.

</Info>

## Configuration

Code length, expiry time, and rate limits are configured by overriding `otpConfig()` in your `AuthOperations` class — see [Auth Operations](/operations/auth-operations). The defaults are a 6-digit code with a 10-minute expiry.

## Using OTP Alongside Password Auth

A table can use both `PasswordAuth` and `OtpAuth` at the same time:

```dart no-analyze
final class UserTable extends AuthTable<User>
    with PasswordAuth, OtpAuth {
  // ...
}
```

Users can sign in via either method. This is useful for offering passwordless sign-in as an alternative, or as a second factor.
