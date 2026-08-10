---
title: Password Auth
description: Email and password authentication with Argon2id hashing.
---

Password authentication is the classic email + password flow. Users sign up with a password, which Zonai hashes with [Argon2id](https://en.wikipedia.org/wiki/Argon2) before storing. The plaintext is never persisted or logged.

## Enabling Password Auth

Add `with PasswordAuth` to your auth table class. This registers the password-related endpoints and adds a `password` column (hashed storage, never returned in API responses):

```dart
final class UserTable extends AuthTable<User>
    with PasswordAuth {
  // ...
}

final users = authTable('users', UserTable.new);
```

## Sign-Up

```
POST /auth/sign-up
```

```json
{
  "type": "signUp",
  "table": "users",
  "email": "alice@example.com",
  "password": "hunter2",
  "object": { "name": "Alice" }
}
```

The optional `object` field passes extra fields to set on the row at creation. Only fields allowed by `signUpFields` in your `AuthOperations` class are accepted.

On success: the row is created with `isVerified = false`, the `onSignUp` extension fires, and the response includes the new user and an `accessToken`.

<Info>

The account starts unverified. Try sending the verification email in your `onSignUp` extension hook and gate sign-in on `canSignIn` checking `isVerified`.

</Info>

## Sign-In

```
POST /auth/sign-in
```

```json
{
  "type": "signIn",
  "table": "users",
  "email": "alice@example.com",
  "password": "hunter2"
}
```

Zonai validates the credentials, evaluates `canSignIn` in auth row rules, fires the `onSignIn` extension, and returns a new `accessToken`.

On invalid credentials: `401 Unauthorized`. The response never indicates whether the email or the password was wrong.

## Email Verification

Email verification is a two-step process:

**Step 1 — Send the verification email:**

```
POST /auth/verify-email
```

```json
{
  "email": "alice@example.com",
  "table": "users"
}
```

Returns `200 OK` with an empty body. Typically you call `email.send.verifyEmail(user)` in the `onSignUp` extension hook instead of requiring clients to call this endpoint directly. Use this endpoint to resend the email.

**Step 2 — Confirm with the token from the email:**

```
POST /auth/confirm
```

```json
{
  "type": "confirmVerifyEmail",
  "token": "abc123..."
}
```

On success: sets `isVerified = true` on the row. Returns `200 OK` with an empty body.

The link format sent in the email is configured via `AuthOperations.verifyEmailConfig()`.

## Password Reset

Password reset is also a two-step process:

**Step 1 — Request the reset email:**

```
POST /auth/reset-password
```

```json
{
  "type": "sendResetPassword",
  "table": "users",
  "email": "alice@example.com"
}
```

Returns `200 OK` with an empty body regardless of whether the email exists. The `canPasswordReset` auth row rule can silently suppress the email (e.g. for unverified accounts).

**Step 2 — Set the new password:**

```
POST /auth/confirm
```

```json
{
  "type": "confirmResetPassword",
  "token": "abc123...",
  "newPassword": "newSecurePass"
}
```

On success: the password is re-hashed and stored. Returns `200 OK` with an empty body.

The reset link format and token expiry are configured via `AuthOperations.resetPasswordConfig()` — see [Auth Operations](/operations/auth-operations).
