---
title: Admin Accounts
description: Creating admin accounts and using elevated JWT claims.
---

Admin accounts are rows in an auth table created via the CLI with elevated JWT claims. Once signed in, admin tokens carry `admin.isAdmin = true`, which your rules can check to grant privileged access.

## Creating an Admin Account

The server does not need to be running. Run this command in your project directory:

```
zonai db admin add --email admin@example.com --password secret123
```

Flags:

| Flag | Short | Required | Description |
|------|-------|----------|-------------|
| `--email` | `-e` | Yes | Email address for the account |
| `--password` | `-p` | Only if the admin table supports password sign-in | Initial password. Omit it entirely on an OAuth-only table — supplying one there is an error, not a silent no-op |
| `--data` | `-d` | No | Extra JSON fields to set on the row (e.g. `--data '{"name":"Admin"}'`) |
| `--no-verify` | | No | Create the account with `isVerified = false` (default: verified) |

Accounts are created with `isVerified = true` by default so they can sign in immediately.

`admin add` resolves the auth types your `AsAdmin` table actually mixes in and
adapts to them — it never assumes password sign-in is configured. If your
admin table mixes in `OAuth` instead of (or in addition to) `PasswordAuth`,
omit `--password`:

```
zonai db admin add --email admin@example.com
```

The account signs in the first time its email matches a verified identity
from one of the table's configured providers — see [OAuth: Signing into the
dashboard with OAuth](/authentication/oauth#signing-into-the-dashboard-with-oauth)
for the end-to-end walkthrough.

## Listing Admin Accounts

```
zonai db admin list
```

Lists every admin account (id, email, and any other non-secret columns). Never prints the password hash.

## Removing an Admin Account

```
zonai db admin remove --email admin@example.com
```

Makes `add` recoverable — a removed email can be re-added later. There is no `--force` on `add` itself; removing first is the deliberate, distinct step.

## Signing In as an Admin

This section covers password sign-in. An admin table configured with `OAuth`
instead signs in through the provider flow described in [OAuth: Signing into
the dashboard with OAuth](/authentication/oauth#signing-into-the-dashboard-with-oauth) —
the elevated JWT claims below are the same either way.

Admin accounts sign in through a dedicated endpoint:

```
POST /auth/admin
```

```json
{
  "type": "adminSignIn",
  "email": "admin@example.com",
  "password": "secret123"
}
```

The response contains an `accessToken` with elevated claims.

## Admin JWT Claims

Tokens issued via `POST /auth/admin` include elevated claims accessible in rules and extensions:

```dart in:expression
jwt?.admin.isAdmin, // true
jwt?.admin.canEdit, // true
```

## Using Admin Claims in Rules

Gate privileged operations on `admin.isAdmin`:

```dart in:table-rules
@override
Future<bool> canDelete(Jwt? jwt) async {
  return jwt?.admin.isAdmin ?? false;
}
```

The `canEdit` flag provides a second, finer-grained permission level — useful when you want some admin users to read but not modify data.

## Changing an Admin Password

If nobody has the current password — the usual reason to reach for this — reset it directly from the CLI. The server does not need to be running:

```
zonai db admin reset-password --email admin@example.com --password newSecurePassword
```

If the admin already knows their password and just wants to change it, use the standard password reset flow (`POST /auth/reset-password`), the admin UI, or update the row directly:

```
PATCH /db
Authorization: Bearer <admin-token>

{ "table": "users", "where": { "id": { "eq": "<adminId>" } }, "updates": [{ "column": "password", "value": "newSecurePassword" }] }
```

The new value is automatically hashed — never store plaintext passwords.
