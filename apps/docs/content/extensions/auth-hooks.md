---
title: Auth Hooks
description: onSignUp, onSignIn, onRefresh, and onLogout extension hooks.
---

Auth hooks fire at key points in the authentication lifecycle. They are available by mixing `AuthExtension` into the extension class for an auth table.

## Enabling Auth Hooks

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

class UserExtensions extends Extension<User> with AuthExtension<User> {
  UserExtensions() : super(users);

  @override
  Future<void> onSignUp(User user, Jwt? jwt) async {
    // ...
  }

  @override
  Future<void> onSignIn(User user, Jwt? jwt) async {
    // ...
  }
}

UserExtensions main() => UserExtensions();
```

## onSignUp(T user, Jwt? jwt)

Fires after the sign-up INSERT commits and the new account row is fully created.

```dart
@override
Future<void> onSignUp(User user, Jwt? jwt) async {
  email.send.verifyEmail(
    EmailAddress(address: user.email),
    table: 'users',
  );

  // Create a companion row (e.g. a billing profile)
  mutate.create.one(
    tableName: 'profiles',
    object: {'user_id': user.id.value},
  );
}
```

## onSignIn(T user, Jwt? jwt)

Fires after credentials are validated and the JWT is about to be issued. Throwing here prevents the token from being returned to the client.

```dart
@override
Future<void> onSignIn(User user, Jwt? jwt) async {
  mutate.update.one(
    table: 'users',
    updates: [Update.column('last_signed_in_at', UpdateValue.literal(DateTime.now()))],
    where: Eq('id', user.id.value),
  );
}
```

Use for: recording last-login timestamp, sending login-notification emails, triggering security alerts.

## onRefresh(T user, Jwt? jwt)

Fires when the client exchanges an existing token for a new one via `POST /auth/refresh`.

```dart
@override
Future<void> onRefresh(User user, Jwt? jwt) async {
  // Update last active timestamp
}
```

## onLogout(T user, Jwt? jwt)

Fires when the current session token is explicitly revoked via `DELETE /auth`. Also fires for each revoked session when `DELETE /auth/all` is called.

```dart
@override
Future<void> onLogout(User user, Jwt? jwt) async {
  // Revoke any push notification subscriptions for this user
}
```
