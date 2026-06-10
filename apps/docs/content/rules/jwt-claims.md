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

`admin.isAdmin` and `admin.canEdit` are only set for admin accounts — accounts created via `zonai db admin add`. Regular user JWTs always have `admin.isAdmin == false`.

`admin.canEdit` is controlled by the `AsAdmin` mixin on the auth table schema. To enable admin accounts on a table, add `with AsAdmin` to the table class:

```dart
final class UserTable extends AuthTable<User> with PasswordAuth, AsAdmin {
  // admin.canEdit defaults to true
}
```

To create read-only admins (they can view but not mutate), override `canEdit` to return `false`:

```dart
final class UserTable extends AuthTable<User> with PasswordAuth, AsAdmin {
  @override
  bool get canEdit => false;
}
```

Then enforce it in your table rules:

```dart
// Allow read for any admin; require canEdit for mutations
@override Future<bool> canView(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;
@override Future<bool> canUpdate(Jwt? jwt) async => jwt?.admin.canEdit ?? false;
@override Future<bool> canDelete(Jwt? jwt) async => jwt?.admin.canEdit ?? false;
```

## Custom Claims

Custom claims are added via `addClaims({required Jwt jwt})` in an auth table's `AuthOperations` class. They are available on the `jwt.claims` map:

```dart
// In AuthOperations:
@override
Future<Claims> addClaims({required Jwt jwt}) async {
  return Claims({'plan': 'pro', 'role': 'editor'});
}

// In a rule:
@override
Future<bool> canCreate(Jwt? jwt) async {
  return jwt?.claims['plan'] == 'pro';
}
```

## Null Safety

The `jwt` parameter is `Jwt?` (nullable). It is `null` when the request has no `Authorization` header. Always handle the null case:

```dart
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

```dart
@override
Future<void> afterCreateSuccess(Task row, Jwt? jwt) async {
  logger.info('Task ${row.id} created by ${jwt?.userId ?? 'anonymous'}');
}
```

## Token Expiry

Expired tokens are rejected automatically by the server — you do not need to check `expiresAt` in rules. Use `POST /auth/refresh` to exchange a valid token for a fresh one before it expires. See [Session Management](/authentication/session-management).
