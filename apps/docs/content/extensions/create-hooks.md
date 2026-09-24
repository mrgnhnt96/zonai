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

Create hooks run for `POST /db` and `POST /db/many` (once per row), and for rows created by `mutate.create` from another hook or a cron job. **Sign-ups do not fire them.** A new account from the auth endpoints fires [`beforeSignUp` and `onSignUp`](/extensions/auth-hooks) instead.

## beforeCreate

Runs after rules pass, before the INSERT executes. **Can abort the operation** by throwing. Nothing is inserted, and the client receives a `500` server error rather than your message:

```dart in:extension-task
@override
Future<void> beforeCreate(Task object, Jwt? jwt) async {
  if (object.title.isEmpty) {
    throw Exception('Title cannot be empty');
  }
}
```

Use for: extra validation beyond what rules check.

Changing `object` here has no effect on what is inserted: the hook receives a copy. To fill in a column the client did not send, patch the new row with `mutate.update` from `afterCreateSuccess`. If the client should see why a create was refused, express the condition as a [row rule](/rules/row-rules) instead.

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
import 'package:my_app/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

class ItemExtensions extends Extension<Item> {
  ItemExtensions() : super(items);

  @override
  Future<void> beforeCreate(Item object, Jwt? jwt) async {
    logger.debug('Creating an item');
  }

  @override
  Future<void> afterCreateSuccess(Item object, Jwt? jwt) async {
    // Patch the new row. Queued, so it runs after this request's INSERT.
    mutate.update.one(
      table: 'items',
      updates: [Update.column('body', .literal('Updated by extension'))],
      where: Eq('id', object.id),
    );
  }
}

ItemExtensions main() => ItemExtensions();
```
