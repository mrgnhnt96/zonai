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

## See also

- **[extensions.md](extensions.md)** — `onSignUp`, `onSignIn`, `onRefresh`, `onLogout` hooks
- **[email.md](email.md)** — SMTP setup, HTML templates, and transactional email
- **[rules.md](rules.md)** — auth collection and row rules
- **[rate-limiting.md](rate-limiting.md)** — `refreshTokenPolicy()` and other auth limits
