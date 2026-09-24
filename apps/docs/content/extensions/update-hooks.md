---
title: Update Hooks
description: beforeUpdate, afterUpdateSuccess, and afterUpdateError extension hooks.
---

## Hook Signatures

```dart in:hook-signatures
Future<void> beforeUpdate(T object, Jwt? jwt);
Future<void> afterUpdateSuccess(T before, T after, Jwt? jwt);
Future<void> afterUpdateError(Object error, Jwt? jwt);
```

`beforeUpdate` receives the row **before** the update is applied. `afterUpdateSuccess` receives **two** row parameters: the state before and the state after the update.

Update hooks run once per matched row, for `PATCH /db`, `PATCH /db/many`, and `mutate.update` calls from other hooks or cron jobs.

## beforeUpdate

Runs after rules pass, before the UPDATE executes. **Can abort** by throwing. Nothing is updated, and the client receives a `500` server error rather than your message:

```dart in:extension-event
@override
Future<void> beforeUpdate(Event object, Jwt? jwt) async {
  if (object.endDate.isBefore(object.startDate)) {
    throw Exception('End date must be after start date');
  }
}
```

Note: `object` here is the **current** row, not the values being applied. The update hasn't happened yet, and the hook cannot see the incoming values. To validate those, use a [row rule](/rules/row-rules).

## afterUpdateSuccess

Runs after the UPDATE commits. Receives both the old and new row states:

```dart in:extension-user
@override
Future<void> afterUpdateSuccess(User before, User after, Jwt? jwt) async {
  if (before.email != after.email) {
    // Email changed — require re-verification
    mutate.update.one(
      table: 'users',
      updates: [Update.column('is_verified', UpdateValue.literal(false))],
      where: Eq('id', after.id.value),
    );
    email.send.verifyEmail(
      EmailAddress(address: after.email),
      table: 'users',
    );
  }
}
```

Use for: detecting field changes, notifying subscribers, resetting verification state.

A `mutate.update` on the same table fires `afterUpdateSuccess` again. Guard it with a condition that becomes false after the first pass, as the `before.email != after.email` check does here. Otherwise the hook keeps re-triggering itself until the [chain limit](/extensions/side-effects-mutate#the-chain-limit) drops the rest.

## afterUpdateError

Runs if the UPDATE fails. Cannot make the operation succeed.

```dart in:extension-user
@override
Future<void> afterUpdateError(Object error, Jwt? jwt) async {
  logger.error('Update failed: $error');
}
```

## Detecting Field Changes

Compare `before.<field>` and `after.<field>` in `afterUpdateSuccess`:

```dart in:side-effects
if (before.title != after.title) {
  // Title changed — reindex the post and notify subscribers
}
```
