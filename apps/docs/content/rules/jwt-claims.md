---
title: JWT Claims
description: What's in the JWT and how to access claims in rules and extensions.
---

The `Jwt` object is passed to every rule and extension method. It contains all the information about who made the request.

## Standard Claims

| Property            | Type       | Description                                                        |
| ------------------- | ---------- | ------------------------------------------------------------------ |
| `jwt.userId`        | `String`   | The `id` of the authenticated row in the auth table                |
| `jwt.table`         | `String`   | Name of the auth table the user signed in through (e.g. `'users'`) |
| `jwt.issuedAt`      | `DateTime` | When the token was created                                         |
| `jwt.expiresAt`     | `DateTime` | When the token expires                                             |
| `jwt.admin.isAdmin` | `bool`     | `true` for admin tokens (created via `zonai db admin add`)         |
| `jwt.admin.canEdit` | `bool`     | `true` if the admin token has edit permission                      |

## Admin Claims

`admin.isAdmin`/`admin.canEdit` are computed **per auth table**, not per row: every JWT issued for *any* row in a table that has `AsAdmin` gets `isAdmin: true` — sign-up, sign-in, OTP, magic link, it doesn't matter which flow authenticated it. There is no per-row "is this specific account an admin" flag.

**`AsAdmin` must only ever go on a dedicated, admin-only auth table — never on a table that also accepts public self-registration.** Putting it on your regular `users` table (or any table reachable through `/auth/sign-up`) gives **every single signed-up user full admin rights**, silently bypassing every `jwt?.admin.isAdmin`/`jwt?.admin.canEdit` check in every rule in your app. This is not a hypothetical: verify it yourself against a real running server — add `AsAdmin` to any table with a `PasswordAuth` sign-up path, sign up a brand-new account, and decode the returned JWT.

Correct usage — a **separate** table, used only for accounts created via `zonai db admin add`:

```dart no-analyze
final class AdminTable extends AuthTable<Admin> with PasswordAuth, AsAdmin {
  // admin.canEdit defaults to true
}
```

Lock down public self-registration on that table too, as defense in depth — `zonai db admin add` bypasses rules entirely (it writes directly, not through `/auth/sign-up`), so this doesn't block legitimate admin creation:

```dart
import 'package:my_app/src/schemas/admins.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class AdminRowRules extends AuthRowRules<AdminTable, Admin> {
  AdminRowRules() : super(admins);

  @override
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async => false;
}
```

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
