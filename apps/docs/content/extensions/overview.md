---
title: Extensions Overview
description: What extensions do and how they fit into the request pipeline.
---

Extensions are lifecycle hooks that run before and after database mutations and auth events. Use them to trigger side effects: send a verification email on sign-up, create a companion row after a create, cascade a deletion, or log what changed.

Extensions are written in Dart and compiled into the extensions worker.

<Info>

Mutations that fire extensions also wake open **stream** subscriptions for affected queries. Clients watching with `db.listen` / `/db/stream*` see updates without polling. See [Streaming](/operations/streaming).

</Info>

## Creating an Extension

Create `<table>_extensions.dart` in `extensionsPath`. Extend `Extension<T>` and override the hooks you need. Export a `main()` function:

```dart
import 'package:my_app/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

class ItemExtensions extends Extension<Item> {
  ItemExtensions() : super(items);

  @override
  Future<void> afterCreateSuccess(Item object, Jwt? jwt) async {
    logger.info('Item ${object.id} created');
    // Queue a mutation, send an email, etc.
  }
}

ItemExtensions main() => ItemExtensions();
```

All hooks default to no-ops. Only override what you need.

## Mutation Hooks

| Hook | When It Runs | Can Abort? |
|------|-------------|-----------|
| `beforeCreate(T object, Jwt? jwt)` | After rules, before INSERT | Yes (throw) |
| `afterCreateSuccess(T object, Jwt? jwt)` | After INSERT succeeds | No |
| `afterCreateError(Object error, Jwt? jwt)` | If INSERT fails | No |
| `beforeUpdate(T object, Jwt? jwt)` | After rules, before UPDATE | Yes (throw) |
| `afterUpdateSuccess(T before, T after, Jwt? jwt)` | After UPDATE succeeds | No |
| `afterUpdateError(Object error, Jwt? jwt)` | If UPDATE fails | No |
| `beforeDelete(T object, Jwt? jwt)` | After rules, before DELETE | Yes (throw) |
| `afterDeleteSuccess(T object, Jwt? jwt)` | After DELETE succeeds | No |
| `afterDeleteError(Object error, Jwt? jwt)` | If DELETE fails | No |

Note: `afterUpdateSuccess` receives **two** row parameters — the row **before** the update and the row **after**.

## Auth Hooks

Mix in `AuthExtension` for auth table hooks:

```dart
class UserExtensions extends Extension<User>
    with AuthExtension<UserTable, User> {
  UserExtensions() : super(users);

  @override
  Future<void> onSignUp(User user) async {
    await email.send.verifyEmail(user);
  }
}
```

Auth hooks: `onSignUp(T user)`, `onSignIn(T user)`, `onRefresh(T user)`, `onLogout(T user)`.

## The 10-Mutation Chain Limit

`afterSuccess` hooks can queue additional mutations via `mutate.*`. Those mutations may trigger their own extensions. Zonai caps this chain at **10 total side-effect mutations** per request to prevent infinite loops. Mutations beyond the limit are silently dropped and a warning is logged.

## Side Effects API

Inside any hook you have access to:
- `get` — read rows from any table
- `mutate` — queue additional writes
- `email` — send transactional email

See the Side Effects pages for details.

## Related

- [Create Hooks](/extensions/create-hooks)
- [Update Hooks](/extensions/update-hooks)
- [Delete Hooks](/extensions/delete-hooks)
- [Auth Hooks](/extensions/auth-hooks)
- [Side Effects: get](/extensions/side-effects-get)
- [Side Effects: mutate](/extensions/side-effects-mutate)
- [Side Effects: email](/extensions/side-effects-email)
