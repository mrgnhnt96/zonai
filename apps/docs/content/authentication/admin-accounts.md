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

## Inviting an Admin

`zonai db admin add` needs a shell in your project directory. Inviting is how an
admin who already has a dashboard adds a colleague without one — and how you add
someone to a table whose only sign-in method belongs to somebody else, such as a
Google-only admin table.

An existing admin sends the invite from the **Admins** screen, or directly:

```
POST /admin/invites
Authorization: Bearer <admin-token>

{ "email": "colleague@example.com" }
```

From a shell — including before any admin exists, when there is no session to
send one with:

```
zonai db admin invite --email colleague@example.com
zonai db admin invites          # what is still outstanding
zonai db admin revoke-invite --email colleague@example.com
```

zonai emails a link to `{baseUrl}/_/admin/invite?token=…` that expires in seven
days. Opening it shows the sign-in methods your admin table declares, and the
screen checks the link is still good before offering anything — an expired or
withdrawn link gets a plain explanation rather than an error page.

What that screen offers depends on the table:

- **OAuth** — a button per provider. Signing in accepts the invite.
- **Password** — a set-password form. Choosing a password creates the account
  and signs you in.
- **OTP or magic link** — an *Accept invitation* button, with nothing to fill
  in. You will sign in with a code or a link from then on.

If your admin table has columns beyond email and password that cannot be empty
— a `name`, say — the acceptance form asks for those too. It is the same set
`zonai db admin add --data` requires.

> **A table that declares OAuth and nothing else can only be accepted through a
> provider**, and the direct path refuses it with a `409`. That is not an
> omission: possession of the invite link proves control of the invited mailbox,
> while an OAuth acceptance additionally has the provider vouch that the account
> signing in owns that address. A table offering only OAuth has chosen the
> stronger check, so zonai will not quietly accept the weaker one on its behalf.

**No admin row exists until the invite is accepted.** That is deliberate: an
unaccepted invite is a pending record, not an account, so a mistyped address
never becomes a half-real admin you have to remember to clean up. The row is
created, the invite consumed, and the session issued in the same step.

Acceptance is always for the address you invited — it is read from the invite,
and no request can name a different one. On the OAuth path there is a second
check on top: the identity signing in must carry a **verified** email equal to
it, so a different Google account following the same link is refused and the
invite stays usable for the person it was meant for.

**A refused acceptance costs nothing.** Every refusal happens before the invite
is consumed, so a mistyped password or a blank required field can simply be
tried again rather than needing a fresh invite.

This is the one place zonai will provision an admin from an external identity
provider. Ordinary OAuth sign-in never creates an admin row, because a provider
that lets anyone register an account would otherwise be a way to register an
admin one.

### Managing invites and admins

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/admin/members` | Current admins and pending invites, in one response |
| `POST` | `/admin/invites` | Invite an address |
| `DELETE` | `/admin/invites/:email` | Revoke a pending invite — the link stops working |
| `DELETE` | `/admin/members/:email` | Remove an admin and revoke their sessions |

Two more are reachable **without** a session, because the invitee has none and
the token in their link is the authorization:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/auth/admin/invite?token=` | Is this link still good? Answers without spending it |
| `POST` | `/auth/admin/invite/accept` | Accept directly — password, OTP or magic-link tables |

Neither distinguishes an expired invite from one that never existed, for the
same reason revoking does not.

Every `/admin/*` route needs an admin token **for that admin table**; anything
else is a `403`. Revoking is idempotent and answers the same way for an address that was
never invited, so it cannot be used to discover who has an invite pending.

Two removals are refused on purpose, and your dashboard should present them as
rules rather than as errors:

- An admin cannot remove **themselves** (`403`).
- The **last** admin cannot be removed at all (`409`). A dashboard that can lock
  everyone out of itself is a bug.

Removing an admin revokes their existing sessions, so a token issued before the
removal stops working immediately rather than lasting until it expires.

Invites are rate limited per admin table and client IP, and repeat invites to one
address are limited to one a minute. The raw invite token exists only in the
email: it is stored hashed, is single-use, and appears in no response body, log
line, or error message.

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
