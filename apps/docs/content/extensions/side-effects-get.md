---
title: "Side Effects: get"
description: Reading rows from any table inside an extension or cron job.
---

`get` is a side-effect API for reading rows from any table inside an extension hook or cron job. Reads use the same JWT from the original request.

## get.one

Fetches a single row matching a condition. Returns `null` if no row matches:

```dart
@override
Future<void> afterCreateSuccess(Comment comment, Jwt? jwt) async {
  final post = await get.one(
    tableName: 'posts',
    where: Eq('id', comment.postId.value),
  );

  if (post != null) {
    logger.info('Comment added to post: ${post['title']}');
  }
}
```

## get.many

Fetches multiple rows. Returns an empty list if none match:

```dart
@override
Future<void> beforeDelete(User user, Jwt? jwt) async {
  final orders = await get.many(
    tableName: 'orders',
    where: Eq('user_id', user.id.value),
    limit: 1,
  ) ?? [];

  if (orders.isNotEmpty) {
    throw Exception('Cannot delete user with orders');
  }
}
```

Optional `limit` and `offset` parameters support pagination.

## Return Type

`get.one` returns `Future<Map<String, Object?>?>` and `get.many` returns `Future<List<Map<String, Object?>>?>`. The results are untyped maps — access fields with `['fieldName']` notation, not dot-property access:

```dart
final row = await get.one(tableName: 'users', where: Eq('id', userId));
final email = row?['email'] as String?;
```

## The Where Clause

`Eq('column', value)` is the simplest condition. More complex queries can be composed using `And`, `Or`, `Gt`, `Lt`, and other `Where` constructors. 
## Rules Apply

`get` calls run through the rules worker using the same JWT from the original request. The same table and row rules that govern the main request apply here — if the requesting user cannot view a table, a `get` call for that table inside an extension will be denied.

## Common Uses

- Fetch the user row to personalize an email after a sign-up
- Check for related rows before allowing a deletion
- Load additional context before sending a notification
- Fetch rows that need processing in a cron job
