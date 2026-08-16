---
title: Auth Tables
description: How to define tables with built-in authentication (password, OTP, magic link).
---

An auth table is a regular table with built-in authentication endpoints. Use `authTable()` instead of `table()`, and extend `AuthTable<T>` instead of `Table<T>`. Mix in one or more auth methods to enable the corresponding sign-in flows.

<Info>

Auth tables still get normal CRUD **and** live streams (`/db/stream*`). After sign-in, use `client.db.listen` for live data — [Streaming](/operations/streaming).

</Info>

## Auth Mixins

| Mixin | Sign-in Method | Docs |
|-------|---------------|------|
| `PasswordAuth` | Email + password | [Password Auth](/authentication/password-auth) |
| `OtpAuth` | One-time passcode via email | [OTP Auth](/authentication/otp-auth) |
| `MagicLinkAuth` | Single-use emailed link | [Magic Link Auth](/authentication/magic-link-auth) |
| `OAuth` | Google, Apple, GitHub and others | [OAuth](/authentication/oauth) |

A table can use multiple mixins simultaneously:

```dart no-analyze
final class UserTable extends AuthTable<User>
    with PasswordAuth, OtpAuth, MagicLinkAuth, OAuth {
  // ...
}
```

`OAuth` is the one mixin with a member you must override — `oauthProviders`,
returning the providers the table accepts. Leaving it out is a compile error.

## Built-in Fields

All auth tables automatically get these columns — you declare them in the class but do not need to define the underlying SQL:

| Column | Method | Type | Notes |
|--------|--------|------|-------|
| `email` | `$.email(...)` | TEXT UNIQUE NOT NULL | The user's identity |
| `isVerified` | `$.isVerified(...)` | BOOL NOT NULL | `false` after sign-up |

`PasswordAuth` adds:

| Column | Method | Type | Notes |
|--------|--------|------|-------|
| `password` | `$.password(...)` | TEXT | Argon2id hash — never returned in responses |

`OtpAuth` and `MagicLinkAuth` add no persistent columns — their tokens are transient.

`OAuth` adds no columns to your table either. The link between a provider
account and a row lives in zonai's internal `_oauth_identities` table, so one
user can sign in with several providers without you modelling it.

## Auth Endpoints

Auth endpoints use the `table` field in the request body to identify which auth table to target. The endpoints themselves are not table-namespaced:

| Endpoint | Description |
|----------|-------------|
| `POST /auth/sign-up` | Create an account (PasswordAuth) |
| `POST /auth/sign-in` | Sign in with email + password (PasswordAuth) |
| `POST /auth` | Request OTP or magic link |
| `POST /auth/confirm` | Verify OTP, magic link, email, or password reset |
| `POST /auth/refresh` | Refresh the access token |
| `DELETE /auth` | Revoke current token (logout) |
| `DELETE /auth/all` | Revoke all tokens (logout everywhere) |
| `POST /auth/reset-password` | Request password reset email |
| `POST /auth/verify-email` | Resend email verification |

See the [Authentication](/authentication/overview) section for request/response shapes.

## Adding Custom Fields

Add any extra columns alongside the built-in auth fields. They are readable and writable via the standard `/db/<table>` API:

```dart no-analyze
final class UserTable extends AuthTable<User> with PasswordAuth {
  UserTable(super.$)
    : id = $.id('id', ...),
      email = $.email('email', ...),
      isVerified = $.isVerified('is_verified', ...),
      name = $.text('name', (s) => s.name),       // custom field
      plan = $.text('plan', (s) => s.plan),        // custom field
      createdAt = $.createdAt('created_at', ...),
      updatedAt = $.updatedAt('updated_at', ...),
      passwordHash = $.password('password', ...);
  // ...
}
```

Custom fields can be embedded in JWT claims via [Auth Operations](/operations/auth-operations).

## Complete Example

```dart
import 'package:my_app/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class User {
  const User({
    required this.id, required this.email, required this.isVerified,
    required this.name, required this.createdAt, this.updatedAt,
    required this.passwordHash,
  });
  final UsersId id;
  final String email;
  final bool isVerified;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String passwordHash;
}

final class UserTable extends AuthTable<User> with PasswordAuth, OtpAuth {
  UserTable(super.$)
    : id = $.id('id', (s) => s.id, fromString: UsersId.new, generate: UsersId.generate),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      name = $.text('name', (s) => s.name),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt),
      passwordHash = $.password('password', (s) => s.passwordHash);

  @override
  User fromRow(RowReader read) => User(
    id: read(id), email: read(email), isVerified: read(isVerified),
    name: read(name), createdAt: read(createdAt), updatedAt: read(updatedAt),
    passwordHash: read(passwordHash),
  );

  final IdColumn<UsersId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final TextColumn name;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
  final PasswordColumn passwordHash;
}

final users = authTable('users', UserTable.new);
```
