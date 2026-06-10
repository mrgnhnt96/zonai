---
title: Auth Rules
description: Controlling sign-up, sign-in, and password reset access.
---

Auth rules control the authentication endpoints (sign-up, sign-in, password reset) for an auth table. They live in the same file as table rules, added as a mixin.

## Enabling Auth Rules

Add `with AuthTableRules<UserTable, User>` to your table rules class:

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserTableRules extends TableRules<UserTable, User>
    with AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);

  // Regular table rules
  @override
  Future<bool> canList(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;

  // Auth rules (default: true — allow)
  @override
  Future<bool> canSignIn(User user) async {
    return user.isVerified;  // block unverified accounts
  }
}
```

<Info>
Auth rule methods default to `true` (allow) when not overridden. This is the opposite of regular table rules, which default to `false` (deny).
</Info>

## Available Methods

### canSignUp(signUpData)

Called before a new account row is created. `signUpData` contains the submitted fields (the password is never exposed):

```dart
@override
Future<bool> canSignUp(SignUpData signUpData) async {
  return signUpData.email.endsWith('@mycompany.com');  // restrict to company domain
}
```

Returning `false` rejects the sign-up with a `403`. Use sparingly — rejecting sign-ups without explanation is confusing for users.

### canSignIn(user)

Called after credentials are validated but before the JWT is issued. `user` is the authenticated row:

```dart
@override
Future<bool> canSignIn(User user) async {
  return user.isVerified;  // block unverified accounts from signing in
}
```

Returning `false` results in `401 Unauthorized` — the user authenticated but was denied a token.

### canPasswordReset(user)

Called before a password reset email is sent. Returning `false` silently suppresses the email (the endpoint still returns `200 OK`):

```dart
@override
Future<bool> canPasswordReset(User user) async {
  return user.isVerified;  // don't send reset emails to unverified accounts
}
```

This is useful when you want to avoid revealing whether an email address is registered.

## Common Patterns

```dart
// Block unverified accounts from signing in
@override Future<bool> canSignIn(User user) async => user.isVerified;

// Restrict sign-up to a company email domain
@override Future<bool> canSignUp(SignUpData data) async =>
    data.email.endsWith('@mycompany.com');

// Prevent password reset for suspended accounts
@override Future<bool> canPasswordReset(User user) async =>
    user.status != 'suspended';
```
