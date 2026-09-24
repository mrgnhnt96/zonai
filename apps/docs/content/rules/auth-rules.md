---
title: Auth Rules
description: Controlling sign-up, sign-in, and password reset access.
---

Auth rules control the authentication endpoints (sign-up, sign-in, password reset) for an auth table. They are split across two classes, the same way ordinary rules are: `AuthTableRules` gates the endpoint for the table as a whole, and `AuthRowRules` gates it for the specific account row involved.

Both are base classes you **extend** — neither is a mixin, and neither is combined with `TableRules`/`RowRules`. An `AuthTable` is not a `Table`, so `TableRules<UserTable, User>` will not even accept an auth table as its type argument.

## Enabling Auth Rules

In `rulesPath`, `<table>_table_rules.dart` extends `AuthTableRules`:

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);

  // Inherited from the ordinary table rules: who may list accounts at all.
  @override
  Future<bool> canList(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;

  // Auth-specific: who may hit the authentication endpoints.
  @override
  Future<bool> canAuthenticate(Jwt? jwt, AuthType authType) async {
    return authType != AuthType.magicLink;  // no magic-link sign-in here
  }
}

UserTableRules main() => UserTableRules();
```

and `<table>_row_rules.dart` extends `AuthRowRules`:

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);

  @override
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async {
    // Invite-only: an existing admin has to be the one creating the account.
    return jwt?.admin.isAdmin ?? false;
  }
}

UserRowRules main() => UserRowRules();
```

<Info>

Auth rules do not receive the account row or the submitted credentials — only the caller's `Jwt?` and the `AuthType` being attempted. Decisions that depend on the row's own columns (`isVerified`, a `status` column) belong in an [extension hook](/extensions/auth-hooks), which does get the row.

</Info>

## AuthType

Every auth rule takes the authentication method being attempted:

```dart no-analyze
enum AuthType { password, otp, magicLink, oauth }
```

This is what lets one rule allow password sign-in while refusing OTP, without touching the other endpoints.

## Available Methods

### canAuthenticate(jwt, authType) — table level

On `AuthTableRules`. Gates the authentication endpoints for the table as a whole. Defaults to `true`.

```dart in:auth-table-rules
@override
Future<bool> canAuthenticate(Jwt? jwt, AuthType authType) async {
  return authType == AuthType.password;  // password only
}
```

`AuthTableRules` also inherits `canCreate`, `canUpdate`, `canDelete`, `canView` and `canList` from the ordinary table rules, all of which take just a `Jwt?` and all of which default to **deny** unless the caller is an admin. See [Table Rules](/rules/table-rules).

### canSignUp(jwt, authType) — row level

On `AuthRowRules`. Called before a new account row is created, and only when no matching row exists yet.

```dart in:auth-row-rules
@override
Future<bool> canSignUp(Jwt? jwt, AuthType authType) async {
  return jwt?.admin.isAdmin ?? false;  // invite-only
}
```

The default:

1. allows an admin token unconditionally;
2. otherwise **denies** every sign-up on a table that mixes in `AsAdmin` (see below);
3. otherwise allows the attempt when the table supports that method — `password` requires `PasswordAuth`, `otp` requires `OtpAuth`, `magicLink` requires `MagicLinkAuth`, `oauth` requires `OAuth`.

#### Sign-up is closed by default on an `AsAdmin` table

`AsAdmin` applies to the whole table: every JWT it issues carries `admin.isAdmin`, however the row came to exist. With open registration, every anonymous `POST /auth/sign-up` would mint a new admin — so `canSignUp` refuses it unless the caller already holds an admin token. `zonai db admin add` is unaffected; it never consults rules. See [JWT Claims](/rules/jwt-claims#admin-claims).

An app that genuinely wants open registration on an admin table opts back in, where a reviewer will see it:

```dart in:project-file
final class AdminRowRules extends AuthRowRules<AdminTable, Admin> {
  AdminRowRules() : super(admins);

  // Deliberate: this table is AsAdmin, so anyone who signs up becomes an
  // admin. Fine for a demo, never for production.
  @override
  Future<bool> canSignUp(Jwt? jwt, AuthType authType) async => true;
}
```

#### `canSignUp` or `beforeSignUp`?

Both refuse a registration before anything is written. The choice is about what you need to see and what the caller is told:

| | `canSignUp` (rule) | `beforeSignUp` ([extension hook](/extensions/auth-hooks)) |
| --- | --- | --- |
| Sees | The JWT and the `AuthType` | Those, plus the submitted email and every extra column in the body |
| Answers with | A `bool` (`403`) | Your own message, returned as a `403` |
| Runs per sign-up | Once | Once for password; at least once for OTP and magic link, which re-run it at verify |

Use the rule when the decision is about the *caller* (an admin token, an auth method this table doesn't offer). Use the hook when it is about the *submission* (the email's domain), or when the caller deserves a reason. The rule runs first; if it returns `false`, the hook is never called.

### canSignIn(jwt, authType) — row level

Called before a token is issued.

```dart in:auth-row-rules
@override
Future<bool> canSignIn(Jwt? jwt, AuthType authType) async {
  return authType != AuthType.otp;  // no OTP sign-in
}
```

Defaults to the same "is this method supported by the table" check as `canSignUp`, without the admin bypass.

### canPasswordReset(jwt, authType) — row level

Called before a password reset email is sent.

```dart in:auth-row-rules
@override
Future<bool> canPasswordReset(Jwt? jwt, AuthType authType) async => false;
```

Defaults to `true` for `AuthType.password` when the table mixes in `PasswordAuth`, and `false` for `otp` and `magicLink` — there is no password to reset on those.

`AuthRowRules` also inherits the row-level `canView`, `canCreate`, `canUpdate` and `canDelete`. Their defaults let an admin through, and otherwise allow only the account whose row ID matches `Jwt.userId` — which is what stops one signed-in user reading another's account row.

Accounts are created through the auth API (`POST /auth/sign-up` and friends), not `POST /db`: a non-admin `create` on an auth table through `/db` is refused regardless of your rules.

## Common Patterns

```dart in:auth-row-rules
// Invite-only: accounts can only be created by an admin
@override
Future<bool> canSignUp(Jwt? jwt, AuthType authType) async =>
    jwt?.admin.isAdmin ?? false;

// Password only -- refuse OTP and magic-link entirely
@override
Future<bool> canAuthenticate(Jwt? jwt, AuthType authType) async =>
    authType == AuthType.password;

// Disable self-service password reset
@override
Future<bool> canPasswordReset(Jwt? jwt, AuthType authType) async => false;
```
