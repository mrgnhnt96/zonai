---
title: JWT Claims
description: What's in the JWT and how to access claims in rules and extensions.
---

The `Jwt` object is passed to every rule and extension method. It contains all the information about who made the request.

## Standard Claims

| Property | Type | Description |
| --- | --- | --- |
| `jwt.userId` | `UnknownId` (an `Id`) | The `id` of the authenticated row in the auth table. Compare with `==` against an `Id` column, or use `.value` for the string |
| `jwt.table` | `String` | Name of the auth table the user signed in through (e.g. `'users'`) |
| `jwt.user` | `Map<String, Object?>` | Snapshot of the user row when the token was issued |
| `jwt.claims` | `Map<String, Object?>` | Custom claims from [`addClaims`](#custom-claims) |
| `jwt.expiresAt` | `DateTime` | When the token expires |
| `jwt.jwtId` | `JwtId` | This token's ID (what logout revokes) |
| `jwt.admin.isAdmin` | `bool` | `true` for tokens issued by an `AsAdmin` table |
| `jwt.admin.canEdit` | `bool?` | `true` if the admin may write; `null` for non-admins |

`jwt.user` is a snapshot: it does not change when the row does. Read the row if a rule needs its current value.

## Admin Claims

`admin.isAdmin`/`admin.canEdit` are computed **per auth table**, not per row: every JWT issued for *any* row in a table that has `AsAdmin` gets `isAdmin: true` — sign-up, sign-in, OTP, magic link, it doesn't matter which flow authenticated it. There is no per-row "is this specific account an admin" flag.

**`AsAdmin` belongs only on a dedicated, admin-only auth table** — never on your regular `users` table or any table people register into. Otherwise every account on it is an admin, and every `jwt?.admin.isAdmin`/`jwt?.admin.canEdit` check in your rules lets them through.

Correct usage — a **separate** table, used only for accounts created with `zonai db admin add` or an [admin invite](/authentication/admin-accounts):

```dart no-analyze
final class AdminTable extends AuthTable<Admin> with PasswordAuth, AsAdmin {
  // admin.canEdit defaults to true
}
```

Public sign-up on an `AsAdmin` table is already refused by the default `canSignUp` (see [Auth Rules](/rules/auth-rules)); don't override it to return `true` unless you mean for every registrant to be an admin.

To create read-only admins (they can view but not mutate), override `canEdit` to return `false` on the same dedicated table:

```dart no-analyze
final class AdminTable extends AuthTable<Admin> with PasswordAuth, AsAdmin {
  @override
  bool get canEdit => false;
}
```

Then enforce it in your table rules (for whichever *other* tables the admin needs to manage — not the admin table itself):

```dart in:table-rules
// Allow read for any admin; require canEdit for mutations
@override Future<bool> canView(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;
@override Future<bool> canUpdate(Jwt? jwt) async => jwt?.admin.canEdit ?? false;
@override Future<bool> canDelete(Jwt? jwt) async => jwt?.admin.canEdit ?? false;
```

## Custom Claims

Custom claims are added via `addClaims({required Jwt jwt})` in an auth table's `AuthOperations` class. They are available on the `jwt.claims` map:

In the table's operations file:

```dart in:auth-operations
@override
Future<Claims> addClaims({required Jwt jwt}) async {
  return Claims({'plan': 'pro', 'role': 'editor'});
}
```

In a rule:

```dart in:table-rules
@override
Future<bool> canCreate(Jwt? jwt) async {
  return jwt?.claims['plan'] == 'pro';
}
```

## Null Safety

The `jwt` parameter is `Jwt?` (nullable). It is `null` when the request has no `Authorization` header. Always handle the null case:

```dart in:table-rules
// Public endpoint — allow anyone
@override
Future<bool> canList(Jwt? jwt) async => true;

// Require sign-in
@override
Future<bool> canCreate(Jwt? jwt) async => jwt != null;

// Require admin
@override
Future<bool> canDelete(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;
```

## JWT in Extensions

Extension hooks also receive `Jwt? jwt`. Use it for audit logging or to make decisions based on who triggered the mutation:

```dart in:extension-task
@override
Future<void> afterCreateSuccess(Task row, Jwt? jwt) async {
  logger.info('Task ${row.id} created by ${jwt?.userId ?? 'anonymous'}');
}
```

## Token Expiry

Expired tokens are rejected automatically by the server — you do not need to check `expiresAt` in rules. Use `POST /auth/refresh` to exchange a valid token for a fresh one before it expires. See [Session Management](/authentication/session-management).
