# Auth and session tokens

Zonai issues **access tokens** (JWTs) when users sign in, sign up, or complete OTP / magic-link flows. Clients send the token on later requests as a bearer credential:

```http
Authorization: Bearer <accessToken>
```

Successful auth responses include a session payload:

```json
{
  "accessToken": "<jwt>",
  "user": { "id": "...", "email": "..." }
}
```

The `user` object is the auth collection row at token issuance. Custom claims from [`AuthOperations.addClaims`](operations.md#auth-collections) are embedded in the JWT, not duplicated in this payload.

## Failed sign-in

**`POST /auth/sign-in` answers a wrong password and an unregistered email identically** — same status, same body — so the endpoint cannot be used to discover whether an address has an account:

```http
401 Unauthorized
{"error": "Invalid password or email"}
```

This holds for `POST /auth` with `"type": "signIn"` and for admin sign-in as well. Two consequences worth stating explicitly, because both were once true and are not:

- **Sign-in never creates the account it was given.** Only `POST /auth/sign-up` (and `POST /auth` with `"type": "signUp"`) provisions. An unknown email is a rejection, not a registration.
- **The message is part of the contract, not just the status.** A distinct body behind the same 401 would be the same oracle one layer down, so every password-path failure renders the string above.

Sign-up has a refusal of its own, and it is a different status on purpose. An app can decline a registration from the `beforeSignUp` extension hook, in which case the endpoint answers:

```text
403 Forbidden
{"error": "Sign-up is limited to Acme staff"}
```

401 means *these credentials are not valid*; this is a well-formed request the app chose to refuse, and the reason is the app's own text rather than a generic `Forbidden`. It runs before the insert, so no account, no session and no verify-email exist afterwards. See [Declining a sign-up](extensions.md#declining-a-sign-up) for what it covers — notably that OTP and magic-link accounts are created at *verify* time, so the code email has already been sent.

The same reasoning is why [the reset-password flow](#reset-password-flow) returns success for an address it has never seen.

Sign-in is not a constant-time operation and does not claim to be: an attacker with a large enough sample and a quiet enough network may still be able to distinguish the branches by timing. What is guaranteed here is that the response itself carries no answer.

One sign-in failure is deliberately *not* rendered this way, and a client that treats every 4xx from this endpoint as "bad credentials" will handle it wrongly: see [Forced password reset](#forced-password-reset).

## Forced password reset

An operator can require an account to **choose a new password before it may sign in again**. The account keeps its current password — the password still verifies — but a password sign-in answers `403` with a one-time reset ticket instead of a session, until a new password is set.

Setting the requirement also **revokes every session the account currently holds**. That is the half that makes it a response to a leaked password rather than a note for later: without it the requirement would bind only sign-ins that have not happened yet, and whoever the password leaked to would keep their session for the rest of `jwtExpiresIn` (14 days by default).

### Setting it

All three of these run from the server box, with no secret, no SMTP and no running server — which is what makes this the recovery path when everything else is locked out:

```bash
# Require it outright. --reason rides to the client in the 403.
zonai db admin require-password-reset --email someone@example.com --reason compromised

# Lift it again, for one set on the wrong address.
zonai db admin require-password-reset --email someone@example.com --clear

# reset-password sets a TEMPORARY password by default: whoever ran the command
# knows it, so the account must choose its own. --no-force-reset opts out.
zonai db admin reset-password --email someone@example.com --password 'temp-1'

# On `add` it is OPT-IN -- the person running `add` is frequently the person
# who will sign in.
zonai db admin add --email someone@example.com --password 'temp-1' --force-reset
```

`--reason` is one of `admin-forced` (the default), `compromised`, `temporary-password` or `password-policy`.

### What the client sees

`POST /auth/sign-in` — and `POST /auth` with `"type": "signIn"`, and `POST /auth/admin`, since all three land on the same password path — answers:

```http
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

> **This body is not shaped like the other auth errors, and that is deliberate.** Every other failure on these endpoints — including the `401` above — answers a bare `{"error": "<sentence>"}` whose *string* is part of the contract. This one answers a structured envelope, because a sentence cannot carry a ticket and cannot be branched on. Only this error speaks it today; migrating the rest is a breaking wire change and has not happened. Branch on `error.code`, never on `error.message`.

Why `403` and not `401`: the whole [failed sign-in](#failed-sign-in) contract rests on `401` meaning *these credentials are not valid*, rendered identically for a wrong password and an unknown address. This response says the opposite — the credentials were correct. And it is not a `200` with no `accessToken`, which every client written before this existed would read as success before failing somewhere further away.

`expiresIn` is in **seconds**. The ticket is short-lived (15 minutes) on purpose: unlike an emailed link, its holder is at the keyboard right now.

### Completing it

The ticket is an ordinary password-reset ticket — the same shape the emailed link carries — so it is redeemed at the endpoint that already exists:

```http
POST /auth/confirm
```
```json
{
  "type": "confirmResetPassword",
  "token": "<the resetToken from the 403>",
  "newPassword": "<the account's own new password>"
}
```

That clears the requirement and revokes sessions again. It returns **no session**: the client signs in again with the new password. Two failures worth handling:

- **`422`** — the submitted password is the one the account already has. The ticket is **not** consumed by this, so the same `resetToken` can be submitted again with a different password. A typo must not cost the recovery path, and on this flow there is no email to re-request.
- **`401`** — the ticket is expired, already used, or was invalidated by a newer sign-in attempt. Sign in again to be issued a fresh one.

An **emailed** reset also clears a forced requirement. The demand is "choose a new password", not "choose it through this particular door".

### What is not gated

The requirement is a statement about the **password** credential. OTP, magic link and OAuth sign-in are untouched: someone who proved possession of their mailbox or their Google account has not used the password, and is not asked to change it. The password stays unusable until they do — an OTP sign-in does not satisfy the requirement.

Design and rationale: [force-password-reset-design.md](force-password-reset-design.md).

## Refreshing a session

Use **`POST /auth/refresh`** to exchange a still-valid access token for a new one without re-entering credentials.

| | |
| --- | --- |
| **Method** | `POST` |
| **Path** | `/auth/refresh` |
| **Body** | None |
| **Headers** | `Authorization: Bearer <current-access-token>` (required) |
| **Response** | Same session payload as sign-in (`accessToken` + `user`) |

Example:

```bash
curl -X POST https://your-app.example/auth/refresh \
  -H "Authorization: Bearer eyJhbGciOi..."
```

### What refresh does

1. Validates the bearer token and resolves the user from the auth collection stored in the JWT.
2. Issues a **new** access token (fresh JWT id, updated claims from `addClaims`).
3. **Revokes** the token presented in the request — it is removed from the internal `_jwt` table.
4. Runs the [`onRefresh`](extensions.md#authextension) extension hook for that auth collection.

After a successful refresh:

- The **new** token works for API calls and for a subsequent refresh.
- The **old** token is rejected for both data requests and another refresh attempt.

Refresh does not re-check the user's password or OTP. It only requires a valid, non-revoked access token.

### Rate limiting

`POST /auth/refresh` is rate-limited per client IP through [`refreshTokenPolicy()`](rate-limiting.md#auth-operations-authcollectionratelimits) on the auth collection. The default is **100 requests per minute** unless you override it in your rate-limit worker.

### Client usage

Store the latest `accessToken` after every sign-in and refresh. When a token is close to expiry (or after a 401), call refresh with the current token and replace the stored value with the new one.

If refresh fails (revoked token, expired token, or user deleted), treat the session as ended and send the user through sign-in again.

## Password management

### How passwords are stored

Passwords are hashed with **Argon2id** (OWASP single-server parameters: 19 MiB memory, 3 iterations, parallelism 1) using a random 16-byte salt per credential. The stored value is `<saltBase64>.<digestBase64>`. The plain-text password is never persisted.

### Changing a user's password (admin UI)

In the admin row-detail panel, the password column is always displayed as `••••••••` — the hash is never shown. Copying the value is disabled.

To set a new password while editing a row, click the **Replace password** icon next to the field. This reveals an empty text input and a generate button. Leaving the field blank (or not clicking the icon at all) leaves the existing password unchanged.

### Changing a user's password (API)

Only an **admin JWT with `canEdit: true`** can update a password column via the update API. Pass the new plain-text password as a string literal — Zonai hashes it automatically before writing to SQLite:

```dart no-analyze
await zonaiDB.update(
  'users',
  UpdatePayload(
    jwt: adminJwt,
    where: Eq('id', userId),
    updates: [ColumnUpdate('password', Literal('new-plain-text-password'))],
  ),
);
```

See [operations.md — Password columns](operations.md#password-columns) for the full rules, error codes, and constraints.

### Reset password flow

To let users change their own password, use the **reset-password email flow** rather than a direct update. The flow sends a time-limited link; when the user follows it, Zonai hashes and stores the new password automatically.

See `resetPasswordConfig` in [operations.md](operations.md#auth-collections) and the `reset_password` email template in [email.md](email.md).

## Related configuration

| Topic | Doc |
| ----- | --- |
| JWT claims, session lifetime, and email link settings | [operations.md](operations.md#auth-collections) |
| Global JWT lifetime (`jwtExpiresIn`, default 14 days) | [config-and-env-flavors.md](config-and-env-flavors.md) |
| Who may sign in / sign up | [rules.md](rules.md#auth-collections) |
| Hooks on refresh (`onRefresh`) | [extensions.md](extensions.md#authextension) |
| Declining a sign-up (`beforeSignUp`) | [extensions.md](extensions.md#declining-a-sign-up) |
| Per-IP refresh limits | [rate-limiting.md](rate-limiting.md#auth-operations-authcollectionratelimits) |
| SMTP, templates, and sending email | [email.md](email.md) |
| Public base URL in auth emails | [server-binding.md](server-binding.md) |
| Admin password update rules and error codes | [operations.md](operations.md#password-columns) |
| Requiring an account to choose a new password | [force-password-reset-design.md](force-password-reset-design.md) |

## Tokens for machines

Everything above is about a credential issued to a person who signed in. A backup script,
a CI job or a partner integration has no password to type and nobody awake to
re-authenticate it — use an [API token](api-tokens.md) instead: issued from the CLI with
no sign-in at all, optionally without an expiry, scoped to named collections, and
revocable on the next request.

## See also

- **[api-tokens.md](api-tokens.md)** — credentials for scripts and integrations
- **[extensions.md](extensions.md)** — `onSignUp`, `onSignIn`, `onRefresh`, `onLogout` hooks
- **[email.md](email.md)** — SMTP setup, HTML templates, and transactional email
- **[sending-email.md](sending-email.md)** — provider, DNS, and credentials for real mail delivery
- **[rules.md](rules.md)** — auth collection and row rules
- **[rate-limiting.md](rate-limiting.md)** — `refreshTokenPolicy()` and other auth limits
- **[admin-invite-design.md](admin-invite-design.md)** — inviting someone to an admin table, and why no admin row exists until the invite is accepted
- **[force-password-reset-design.md](force-password-reset-design.md)** — where the requirement lives, why the gate runs before a JWT exists, and why this one error speaks a structured envelope
