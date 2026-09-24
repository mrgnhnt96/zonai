---
title: Password Auth
description: Email and password authentication with Argon2id hashing.
---

Password authentication is the classic email + password flow. Users sign up with a password, which Zonai hashes with [Argon2id](https://en.wikipedia.org/wiki/Argon2) before storing. The plaintext is never persisted or logged.

## Enabling Password Auth

Add `with PasswordAuth` to your auth table class. This registers the password-related endpoints and adds a `password` column (hashed storage, never returned in API responses):

```dart no-analyze
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
  "table": "users",
  "email": "alice@example.com",
  "password": "hunter2",
  "object": { "name": "Alice" }
}
```

`table` defaults to `"users"` when omitted. The optional `object` field passes extra fields to set on the row at creation. Only fields allowed by `signUpFields` in your `AuthOperations` class are accepted. The same request can go to `POST /auth` with `"type": "signUp"`.

On success: the row is created with `isVerified = false`, the `onSignUp` extension fires, and the response includes the new user and an `accessToken`.

<Info>

The account starts unverified. Try sending the verification email in your `onSignUp` extension hook and gate sign-in on `canSignIn` checking `isVerified`.

</Info>

### Declining a sign-up

An app can refuse a registration from the `beforeSignUp` extension hook by throwing `SignUpDeclinedException`:

```dart in:extension-user
@override
Future<void> beforeSignUp(SignUpCandidate candidate, Jwt? jwt) async {
  if (!candidate.email.endsWith('@acme.com')) {
    throw const SignUpDeclinedException('Sign-up is limited to Acme staff');
  }
}
```

The endpoint then answers `403` with that reason, verbatim — so put nothing in it the caller should not see:

```text
403 Forbidden
{"error": "Sign-up is limited to Acme staff"}
```

This is a different status from a failed sign-in on purpose: `401` means *these credentials are not valid*; this is a well-formed request the app chose to refuse. The hook runs before the insert, so a refusal leaves no account, no session and no verify-email. Any other exception from the hook also aborts the sign-up, but as a `500`. On OTP and magic link the hook runs at both the request and the verify, so a hook with side effects must tolerate running twice. See [Auth Hooks](/extensions/auth-hooks).

### Signing up an email that already exists

**Sign-up on an existing account signs that account in** — it does not return a conflict. If no account exists for the email, one is created; if one does, the credentials are checked and a session is issued. This is the same behaviour [magic link](/authentication/magic-link-auth) and [OTP](/authentication/otp-auth) have.

So, given an email that is already registered:

| Password submitted | Result |
|---|---|
| Matches the account | `200` with that account and a fresh `accessToken` — **no second row, no `onSignUp` hook** |
| Does not match | `401 Invalid password or email` |

Two consequences worth designing around:

- **A retried sign-up is safe.** A client that resends after a network timeout gets the original account back rather than an error, so it needs no "already exists" special case.
- **It will not tell you an email is taken.** If your UI needs that — to say "this address is registered, sign in instead" — check for the account yourself rather than relying on sign-up to fail. A wrong password returns the same `401` as a genuinely wrong sign-in, so the response alone cannot distinguish "taken" from "bad credentials".

This does not let anyone into an account whose password they do not have: a caller without the real password gets a normal `401`.

## Sign-In

```
POST /auth/sign-in
```

```json
{
  "table": "users",
  "email": "alice@example.com",
  "password": "hunter2"
}
```

Zonai validates the credentials, evaluates `canSignIn` in auth row rules, fires the `onSignIn` extension, and returns a new `accessToken`. `POST /auth` with `"type": "signIn"` is the same operation.

**Sign-in never creates an account.** Only sign-up provisions. An unknown email is a rejection, not a registration.

### Failed sign-in

A wrong password and an unregistered email answer **identically** — same status, same body — so the endpoint cannot be used to discover whether an address has an account:

```text
401 Unauthorized
{"error": "Invalid password or email"}
```

This holds for `POST /auth/sign-in`, `POST /auth` with `"type": "signIn"`, and admin sign-in (`POST /auth/admin`). The message is part of the contract, not just the status. An account that exists but has no password (OTP-only, say) gets the same answer.

Sign-in is not constant-time: an attacker with a large enough sample may still distinguish the branches by timing. What is guaranteed is that the response carries no answer.

One sign-in failure is deliberately **not** a `401`: a correct password on an account that owes a new one answers `403`. A client that treats every 4xx from sign-in as "bad credentials" handles it wrongly — see [Forced Password Reset](#forced-password-reset).

## Email Verification

Email verification is a two-step process.

**Step 1 — Send the verification email** (requires the user's own session):

```
POST /auth/verify-email
Authorization: Bearer <accessToken>
```

The email goes to the address on the signed-in user's own row, so no body is needed. An admin token may instead name another account with a body of `{"email": "...", "table": "users"}`; a non-admin's body is ignored. Returns `200 OK` with an empty body.

Typically you call `email.send.verifyEmail(user)` in the `onSignUp` extension hook instead of requiring clients to call this endpoint. Use the endpoint for "resend".

**Step 2 — Confirm with the token from the email.** The emailed link is `{baseUrl}{path}?s=<token>`, where `path` comes from `AuthOperations.verifyEmailConfig()` (default `/auth/verify-email`, valid 24 hours). The page at that URL is yours to serve; it reads `s` and posts it back:

```
POST /auth/confirm
```

```json
{
  "type": "confirmVerifyEmail",
  "token": "<the s query parameter>"
}
```

On success: sets `isVerified = true` on the row. Returns `200 OK` with an empty body.

## Password Reset

Password reset is also a two-step process.

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

Returns `200 OK` with an empty body regardless of whether the email exists — an unknown address looks exactly like a known one. For an existing account, the `canPasswordReset` auth row rule decides whether it may use the flow at all, and a refusal answers `403`. One reset email per address per minute; a second request inside the minute answers `429`.

**Step 2 — Set the new password.** The emailed link is `{baseUrl}{path}?s=<token>`, where `path` comes from `AuthOperations.resetPasswordConfig()` (default `/auth/reset-password`, valid 10 minutes). Your page reads `s` and posts it with the new password:

```
POST /auth/confirm
```

```json
{
  "type": "confirmResetPassword",
  "token": "<the s query parameter>",
  "newPassword": "newSecurePass"
}
```

On success: the password is re-hashed and stored, **every session the account holds is revoked**, and the response is `200 OK` with an empty body — **no session**. The client signs in again with the new password.

| Status | Meaning |
|---|---|
| `401` | The token is expired, already used, or unknown. Request a new email. |
| `422` | `newPassword` is the password the account already has. The token is **not** consumed, so the same token can be resubmitted with a different password. |

See [Auth Operations](/operations/auth-operations) for `resetPasswordConfig()` and `verifyEmailConfig()`, and [Built-in Templates](/email/built-in-templates) for the emails themselves.

## Forced Password Reset

An operator can require an account to **choose a new password before it may sign in again**. The account keeps its current password — it still verifies — but a password sign-in answers `403` with a one-time reset ticket instead of a session, until a new password is set.

Setting the requirement also **revokes every session the account currently holds**. That is what makes it a response to a leaked password: without it, whoever the password leaked to would keep their session for the rest of `jwtExpiresIn`.

### Setting it

From the dashboard's row detail panel on any collection with a password column, or from the CLI for the admin table. The CLI needs no secret, no SMTP and no running server — which is what makes it the recovery path when everything else is locked out:

```bash
# Require it outright. --reason rides to the client in the 403.
zonai db admin require-password-reset --email someone@example.com --reason compromised

# Lift it again, for one set on the wrong address.
zonai db admin require-password-reset --email someone@example.com --clear

# reset-password sets a TEMPORARY password by default: whoever ran the command
# knows it, so the account must choose its own. --no-force-reset opts out.
zonai db admin reset-password --email someone@example.com --password 'temp-1'

# On `add` it is OPT-IN -- the person running `add` is usually the person
# who will sign in.
zonai db admin add --email someone@example.com --password 'temp-1' --force-reset
```

`--reason` is one of `admin-forced` (the default), `compromised`, `temporary-password` or `password-policy`. The same actions are available to an admin over HTTP:

| Method | Path | |
|---|---|---|
| `POST` | `/admin/members/:email/require-password-reset?table=users&reason=compromised` | Set it (and revoke sessions) |
| `GET` | `/admin/members/:email/require-password-reset?table=users` | Read the standing requirement, or `null` |
| `DELETE` | `/admin/members/:email/require-password-reset?table=users` | Lift it |

### What the client sees

`POST /auth/sign-in`, `POST /auth` with `"type": "signIn"`, and `POST /auth/admin` all answer:

```text
403 Forbidden
```

```json
{
  "error": {
    "code": "password_reset_required",
    "message": "This account must set a new password before signing in",
    "details": {
      "resetToken": "<one-time ticket>",
      "expiresIn": 900,
      "reason": "temporaryPassword"
    }
  }
}
```

<Warning>

**This body is not shaped like the other auth errors.** Every other failure on these endpoints answers a bare `{"error": "<sentence>"}`. This one is a structured envelope, because a sentence cannot carry a ticket and cannot be branched on. Branch on `error.code`, never on `error.message`.

</Warning>

- `expiresIn` is in **seconds**. The ticket lives 15 minutes: its holder is at the keyboard right now.
- `reason` is `adminForced`, `compromised`, `temporaryPassword` or `passwordPolicy` — use it to say something truer than "you must reset". Treat unknown values as `adminForced`; new ones may be added.
- It is `403`, not `401`, because the credentials were *correct*; and not a `200` without a token, which older clients would read as success.

### Completing it

The ticket is an ordinary password-reset token, redeemed at the same endpoint as the emailed link:

```
POST /auth/confirm
```

```json
{
  "type": "confirmResetPassword",
  "token": "<the resetToken from the 403>",
  "newPassword": "<the account's own new password>"
}
```

That clears the requirement and revokes sessions again. It returns **no session**: sign in again with the new password. A `422` (same password as before) does **not** consume the ticket — resubmit with a different password; on this flow there is no email to re-request. A `401` means the ticket expired, was used, or was replaced by a newer sign-in attempt — sign in again to be issued a fresh one.

An **emailed** reset also satisfies the requirement. The Dart client wraps all of this in `PasswordResetRequiredException` and `completePasswordReset` — see [Dart client authentication](/dart-client/authentication#forced-password-reset).

### What is not gated

The requirement is about the **password** credential only. OTP, magic link and OAuth sign-in are untouched: someone who proved possession of their mailbox or provider account has not used the password. The password stays unusable until it is changed — an OTP sign-in does not satisfy the requirement.

## How Passwords Are Stored

Argon2id with OWASP single-server parameters — 19 MiB memory, 3 iterations, parallelism 1 — and a random 16-byte salt per credential. The stored value is `<saltBase64>.<digestBase64>`.

The dashboard never displays the hash: the password field shows `••••••••` and cannot be copied. To set a new one while editing a row, click the **Replace password** icon beside the field; leaving it untouched keeps the existing password. Over the API, only an admin token with `canEdit` may write a password column, and it sends the plaintext — Zonai hashes it before writing. See [Admin Accounts](/authentication/admin-accounts#changing-an-admin-password).
