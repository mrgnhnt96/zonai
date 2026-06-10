---
title: "Side Effects: mutate"
description: Queuing additional database writes inside an extension or cron job.
---

`mutate` is a side-effect API for queuing additional database writes from inside extension hooks and cron jobs. Calls are synchronous (fire-and-forget) — they are queued and execute after the current hook returns.

## mutate.create

Insert one or more rows into a table:

```dart
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

```dart
// Update one row (limit: 1 applied automatically)
mutate.update.one(
  table: 'users',
  updates: [Update.column('last_signed_in_at', .literal(DateTime.now()))],
  where: Eq('id', user.id.value),
);

// Update many rows
mutate.update.many(
  tableName: 'posts',
  updates: [Update.column('author_name', .literal(user.displayName))],
  where: Eq('author_id', user.id.value),
);
```

Note: `update.one` uses the named parameter `table:` while all other mutate methods use `tableName:`.

## mutate.delete

Delete one or more rows:

```dart
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

Mutations queue in the order they are called and execute after the hook returns. Each executed mutation goes through the full pipeline — rules, rate limit, extensions — for the target table. This means:

- A delete on `comments` triggers `CommentExtensions.afterDeleteSuccess`
- That hook could queue further mutations, up to the chain limit

## The Chain Limit

A single request chain can trigger at most **10 side-effect mutations**. This prevents infinite loops (e.g. an update extension that updates the same row indefinitely). Mutations beyond the limit are silently dropped and a warning is logged.

## Example: Audit Log

```dart
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
