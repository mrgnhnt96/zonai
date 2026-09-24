---
title: "Side Effects: mutate"
description: Queuing additional database writes inside an extension or cron job.
---

`mutate` is a side-effect API for queuing additional database writes from inside extension hooks and cron jobs. Calls return `void` immediately. The write is queued and runs after the request's own write and hooks have finished (for a cron job, after `run()` returns). A queued write is not visible to a `get` in the same hook, and the hook cannot see how many rows it changed.

## mutate.create

Insert one or more rows into a table:

```dart in:side-effects
// Insert one row
mutate.create.one(
  tableName: 'audit_log',
  object: {
    'action': 'delete',
    'table': 'posts',
    'row_id': post.id.value,
    'actor_id': jwt?.userId,
  },
);

// Insert multiple rows
mutate.create.many(
  tableName: 'notifications',
  objects: recipientIds.map((id) => {'user_id': id, 'message': '...'}).toList(),
);
```

## mutate.update

Update one or more rows:

```dart in:side-effects
// Update one row (limit: 1 applied automatically)
mutate.update.one(
  table: 'users',
  updates: [Update.column('last_signed_in_at', .literal(DateTime.now()))],
  where: Eq('id', user.id.value),
);

// Update many rows
mutate.update.many(
  tableName: 'posts',
  updates: [Update.column('author_name', .literal(user.name))],
  where: Eq('author_id', user.id.value),
);
```

Note: `update.one` uses the named parameter `table:` while all other mutate methods use `tableName:`.

## mutate.delete

Delete one or more rows:

```dart in:side-effects
// Delete one row
mutate.delete.one(
  tableName: 'sessions',
  where: Eq('id', sessionId),
);

// Delete many rows
mutate.delete.many(
  tableName: 'comments',
  where: Eq('post_id', post.id.value),
);
```

## Queuing Behavior

Mutations run in the order they were queued. Each one goes through the same pipeline as an HTTP request to the target table: table rules, row rules, operations, and that table's extension hooks. (Rate limits are not applied; they only guard HTTP routes.) This means:

- A delete on `comments` triggers `CommentExtensions.afterDeleteSuccess`
- That hook could queue further mutations, up to the chain limit

**Queued writes act as the hook's `jwt`.** A write queued from a user's request is checked against that user's rules, so the user needs permission to write the target table. In cron jobs the identity is `CronJwt`.

**Queued writes only run if the request succeeds.** If a `before*` hook throws, the write itself fails, or an `after*Success` hook throws, everything queued so far is discarded. Writes queued in `after*Error` hooks never run either, because the request is failing.

## The Chain Limit

Queued writes run in rounds. The writes queued by the request form round one; the writes their hooks queue form round two, and so on. After **10 rounds**, anything still queued is dropped **silently**, with no error and no log line. This stops loops such as an update hook that keeps updating its own row.

Within a round, all the writes are committed in one transaction.

## Example: Audit Log

```dart
import 'package:my_app/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

class PostExtensions extends Extension<Post> {
  PostExtensions() : super(posts);

  @override
  Future<void> afterDeleteSuccess(Post post, Jwt? jwt) async {
    mutate.create.one(
      tableName: 'audit_log',
      object: {
        'action': 'post_deleted',
        'post_id': post.id.value,
        'deleted_by': jwt?.userId,
      },
    );
  }
}

PostExtensions main() => PostExtensions();
```
