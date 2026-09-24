---
title: Authentication Overview
description: How Zonai's JWT-based authentication works end to end.
---

Zonai provides a complete authentication system for any table defined with `authTable()`. Sign-up, sign-in, token refresh, and logout are handled automatically — no route handlers to write.

<Info>

After you have a JWT, live UI should subscribe with `client.db.listen` / `GET /db/stream*` — not a poll loop. See [Streaming](/operations/streaming).

</Info>

## The Auth Model

Authentication is JWT-based. When a user signs in, Zonai issues a signed JSON Web Token. The client includes it on every subsequent request as a `Bearer` token:

```
Authorization: Bearer <accessToken>
```

The server checks the signature and then looks the token's id up in the internal `_jwt` table on every request — one indexed read — which is what lets a logout or revocation take effect immediately rather than at expiry.

Most auth request bodies include a `table` field identifying which auth table the request targets (e.g. `"users"`). This lets a single server host multiple auth tables — users, admins, or any other authenticated entity — under the same set of endpoints.

## Sign-In Flow

1. Client POSTs credentials to the appropriate auth endpoint with the target `table`.
2. Auth rules evaluate the relevant check (e.g. `canSignIn`).
3. Auth operations validate the credentials (same runtime as other ops).
4. On success, Zonai issues a signed JWT and fires the `onSignIn` extension hook.
5. The token is returned in the response.

All subsequent requests include `Authorization: Bearer <token>`.

## Response Format

Successful auth responses (sign-up, sign-in, OTP verify, magic link verify, refresh) return:

```json
{
  "data": {
    "accessToken": "eyJhbGciOiJIUzI1NiJ9...",
    "user": {
      "id": "abc_us",
      "email": "alice@example.com",
      "is_verified": false,
      "created_at": "2024-01-01T00:00:00.000Z"
    }
  }
}
```

The `user` object is the auth table row at the moment the token was issued (the `password` column is never included). Custom claims from `AuthOperations.addClaims` are embedded in the JWT, not repeated here. The same token is also returned in an `X-Auth` response header, which is how the [Dart client](/dart-client/authentication) picks it up without parsing the body.

Errors on the auth endpoints are a bare `{"error": "<sentence>"}` with the status carrying the meaning — `401` for credentials that are not valid, `403` for a request that was understood and refused. The one exception is [forced password reset](/authentication/password-auth#forced-password-reset), which answers a structured `{"error": {"code": ...}}` envelope.

Email-sending endpoints (request OTP, request magic link, request password reset, resend verify email) return an empty `200 OK`. They never reveal whether the email address exists in the database.

## Supported Auth Methods

A single auth table can use one or more of these simultaneously:

| Mixin | Description |
|-------|-------------|
| `PasswordAuth` | Email and password sign-in |
| `OtpAuth` | One-time passcode delivered via email |
| `MagicLinkAuth` | Passwordless sign-in via an emailed link |
| `OAuth` | Sign in with Google, Apple, GitHub and other providers — see [OAuth](/authentication/oauth) |

See [Auth Tables](/schemas/auth-tables) for how to add them to a table.

Already running Supabase Auth, Auth0, Clerk or another identity provider? Zonai can trust its JWTs instead of issuing its own — see [External Identity Providers](/authentication/external-idp).

## Tokens for Machines

Everything above assumes a person who signed in. A script, a CI job or a partner integration has no password to type and nobody awake to re-authenticate it when its token lapses — see [API Tokens](/authentication/api-tokens) for a credential that needs neither.

## Token Lifetime

Tokens expire after 24 hours by default. This is configured globally via `AppConfig.jwtExpiresIn`, and can be overridden per auth table by overriding the `jwtExpiresIn` getter in its `AuthOperations` class. After expiry, requests with the token return `401 Unauthorized`. See [Session Management](/authentication/session-management) for how to refresh tokens.

## Token Revocation

Issued tokens are tracked in the internal `_jwt` table. `DELETE /auth` revokes the current session's token immediately; `DELETE /auth/all` revokes every active token for that user. Revoked tokens return `401` even before they would naturally expire.
