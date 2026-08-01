---
title: Authentication Overview
description: How Zonai's JWT-based authentication works end to end.
---

Zonai provides a complete authentication system for any table defined with `authTable()`. Sign-up, sign-in, token refresh, and logout are handled automatically — no route handlers to write.

<Info>
After you have a JWT, live UI should subscribe with `client.db.listen` / `GET /db/stream*` — not a poll loop. See [Streaming](/operations/streaming).
</Info>

## The Auth Model

Authentication is JWT-based. When a user signs in, Zonai issues a signed JSON Web Token. The client includes it on every subsequent request as a `Bearer` token. Tokens are self-contained: the server verifies them cryptographically without a database lookup on each request.

Most auth request bodies include a `table` field identifying which auth table the request targets (e.g. `"users"`). This lets a single server host multiple auth tables — users, admins, or any other authenticated entity — under the same set of endpoints.

## Sign-In Flow

1. Client POSTs credentials to the appropriate auth endpoint with the target `table`.
2. Auth rules evaluate the relevant check (e.g. `canSignIn`) — in-process on the default path.
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
      "isVerified": false,
      "createdAt": "2024-01-01T00:00:00.000Z"
    }
  }
}
```

The `user` object contains all columns from the auth table row (the `password` column is never included). The `accessToken` is the JWT to send in the `Authorization` header.

Email-sending endpoints (request OTP, request magic link, request password reset, resend verify email) return an empty `200 OK`. They never reveal whether the email address exists in the database.

## Supported Auth Methods

A single auth table can use one or more of these simultaneously:

| Mixin | Description |
|-------|-------------|
| `PasswordAuth` | Email and password sign-in |
| `OtpAuth` | One-time passcode delivered via email |
| `MagicLinkAuth` | Passwordless sign-in via an emailed link |

See [Auth Tables](/schemas/auth-tables) for how to add them to a table.

## Token Lifetime

Tokens expire after 14 days by default. This is configured globally via `AppConfig.jwtExpiresIn`, and can be overridden per auth table in its `AuthOperations` class. After expiry, requests with the token return `401 Unauthorized`. See [Session Management](/authentication/session-management) for how to refresh tokens.

## Token Revocation

Issued tokens are tracked in the internal `_jwt` table. `DELETE /auth` revokes the current session's token immediately; `DELETE /auth/all` revokes every active token for that user. Revoked tokens return `401` even before they would naturally expire.
