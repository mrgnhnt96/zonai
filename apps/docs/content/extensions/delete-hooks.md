---
title: Delete Hooks
description: beforeDelete, afterDeleteSuccess, and afterDeleteError extension hooks.
---

## Hook Signatures

```dart
Future<void> beforeDelete(T object, Jwt? jwt)
Future<void> afterDeleteSuccess(T object, Jwt? jwt)
Future<void> afterDeleteError(Object error, Jwt? jwt)
```

`object` in all delete hooks is the row being (or that was) deleted.

## beforeDelete

Runs after rules pass, before the DELETE executes. **Can abort** by throwing:

```dart
@override
Future<void> beforeDelete(User user, Jwt? jwt) async {
  final orders = await get.many(
    tableName: 'orders',
    where: Eq('user_id', user.id.value),
    limit: 1,
  ) ?? [];
  if (orders.isNotEmpty) {
    throw Exception('Cannot delete user with open orders');
  }
}
```

Use for: checking for dependencies before deleting, implementing soft-delete (throw to prevent deletion, then update a `deletedAt` column instead).

## afterDeleteSuccess

Runs after the DELETE commits. The row is gone — this hook cannot undo the deletion.

```dart
@override
Future<void> afterDeleteSuccess(Post post, Jwt? jwt) async {
  // Cascade: delete all comments on this post
  mutate.delete.many(
    tableName: 'comments',
    updates: [],
    where: Eq('post_id', post.id.value),
  );
}
```

Each cascaded deletion goes through the full pipeline — row rules and extensions on `comments` also fire.

Use for: cascading deletes, releasing associated resources (photos, uploads), notifying external systems.

## afterDeleteError

Runs if the DELETE fails. Cannot make the operation succeed.

```dart
@override
Future<void> afterDeleteError(Object error, Jwt? jwt) async {
  logger.error('Delete failed: $error');
}
```

## Example: Cascade Delete

```dart
class PostExtensions extends Extension<Post> {
  PostExtensions() : super(posts);

  @override
  Future<void> afterDeleteSuccess(Post post, Jwt? jwt) async {
    // Delete comments first, which triggers CommentExtensions hooks
    await mutate.delete.many(
      table: 'comments',
      where: Eq('post_id', post.id.value),
    );

    // Also delete the post's cover photo if one exists
    if (post.coverPhotoId != null) {
      mutate.delete.one(
        tableName: '_photos',
        updates: [],
        where: Eq('id', post.coverPhotoId),
      );
    }
  }
}

PostExtensions main() => PostExtensions();
```
