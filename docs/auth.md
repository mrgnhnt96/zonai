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

The same reasoning is why [the reset-password flow](#reset-password-flow) returns success for an address it has never seen.

Sign-in is not a constant-time operation and does not claim to be: an attacker with a large enough sample and a quiet enough network may still be able to distinguish the branches by timing. What is guaranteed here is that the response itself carries no answer.

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
| Per-IP refresh limits | [rate-limiting.md](rate-limiting.md#auth-operations-authcollectionratelimits) |
| SMTP, templates, and sending email | [email.md](email.md) |
| Public base URL in auth emails | [server-binding.md](server-binding.md) |
| Admin password update rules and error codes | [operations.md](operations.md#password-columns) |

## See also

- **[extensions.md](extensions.md)** — `onSignUp`, `onSignIn`, `onRefresh`, `onLogout` hooks
- **[email.md](email.md)** — SMTP setup, HTML templates, and transactional email
- **[rules.md](rules.md)** — auth collection and row rules
- **[rate-limiting.md](rate-limiting.md)** — `refreshTokenPolicy()` and other auth limits
