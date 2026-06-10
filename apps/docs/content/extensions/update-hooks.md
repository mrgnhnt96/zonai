---
title: Update Hooks
description: beforeUpdate, afterUpdateSuccess, and afterUpdateError extension hooks.
---

## Hook Signatures

```dart
Future<void> beforeUpdate(T object, Jwt? jwt)
Future<void> afterUpdateSuccess(T before, T after, Jwt? jwt)
Future<void> afterUpdateError(Object error, Jwt? jwt)
```

`beforeUpdate` receives the row **before** the update is applied. `afterUpdateSuccess` receives **two** row parameters: the state before and the state after the update.

## beforeUpdate

Runs after rules pass, before the UPDATE executes. **Can abort** by throwing:

```dart
@override
Future<void> beforeUpdate(Event object, Jwt? jwt) async {
  if (object.endDate.isBefore(object.startDate)) {
    throw Exception('End date must be after start date');
  }
}
```

Note: `object` here is the **current** row, not the values being applied. The update hasn't happened yet.

## afterUpdateSuccess

Runs after the UPDATE commits. Receives both the old and new row states:

```dart
@override
Future<void> afterUpdateSuccess(User before, User after, Jwt? jwt) async {
  if (before.email != after.email) {
    // Email changed — require re-verification
    await mutate.update.one(
      table: 'users',
      updates: [Update.column('is_verified', UpdateValue.literal(false))],
      where: Eq('id', after.id.value),
    );
    await email.send.verifyEmail(after);
  }
}
```

Use for: detecting field changes, notifying subscribers, resetting verification state.

## afterUpdateError

Runs if the UPDATE fails. Cannot make the operation succeed.

```dart
@override
Future<void> afterUpdateError(Object error, Jwt? jwt) async {
  logger.error('Update failed: $error');
}
```

## Detecting Field Changes

Compare `before.<field>` and `after.<field>` in `afterUpdateSuccess`:

```dart
if (before.status != after.status && after.status == 'published') {
  // Post was just published — send notifications
}
```
