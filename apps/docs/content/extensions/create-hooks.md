---
title: Create Hooks
description: beforeCreate, afterCreateSuccess, and afterCreateError extension hooks.
---

## Hook Signatures

```dart in:hook-signatures
Future<void> beforeCreate(T object, Jwt? jwt);
Future<void> afterCreateSuccess(T object, Jwt? jwt);
Future<void> afterCreateError(Object error, Jwt? jwt);
```

The `object` in `beforeCreate` contains the data to be inserted (not yet in the database). The `object` in `afterCreateSuccess` is the committed row, including generated fields like `id` and `createdAt`.

## beforeCreate

Runs after rules pass, before the INSERT executes. **Can abort the operation** by throwing — the exception message is returned as a `400` to the client:

```dart in:extension-task
@override
Future<void> beforeCreate(Task object, Jwt? jwt) async {
  if (object.title.isEmpty) {
    throw Exception('Title cannot be empty');
  }
}
```

Use for: extra validation beyond what rules check, setting default values before insert.

## afterCreateSuccess

Runs after the INSERT commits. Cannot abort — the row is already in the database.

```dart in:extension-user
@override
Future<void> afterCreateSuccess(User user, Jwt? jwt) async {
  email.send.verifyEmail(
    EmailAddress(address: user.email),
    table: 'users',
  );
}
```

Use for: sending welcome or verification emails, creating companion rows, logging new signups, incrementing counters.

## afterCreateError

Runs if the INSERT fails. Cannot make the operation succeed.

```dart in:extension-user
@override
Future<void> afterCreateError(Object error, Jwt? jwt) async {
  logger.error('Create failed: $error');
}
```

Use for: logging unexpected insert failures, alerting on anomalies.

## Example

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserExtensions extends Extension<User> with AuthExtension<User> {
  UserExtensions() : super(users);

  @override
  Future<void> onSignUp(User user, Jwt? jwt) async {
    email.send.verifyEmail(
      EmailAddress(address: user.email),
      table: 'users',
    );

    // Create a companion profile row
    mutate.create.one(
      tableName: 'profiles',
      object: {'user_id': user.id.value, 'displayName': user.email},
    );
  }
}

UserExtensions main() => UserExtensions();
```
