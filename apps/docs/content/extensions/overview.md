---
title: Extensions Overview
description: What extensions do and how they fit into the request pipeline.
---

Extensions are lifecycle hooks that run before and after database mutations and auth events. Use them to trigger side effects: send a verification email on sign-up, create a companion row after a create, cascade a deletion, or log what changed.

Extensions do not replace [rules](/rules/overview) or [operations](/operations/overview). Rules decide *whether* a request is allowed and operations build its SQL. Extensions run *before or after* the write to react to it.

<Info>

Mutations that fire extensions also wake open **stream** subscriptions for affected queries. Clients watching with `db.listen` / `/db/stream*` see updates without polling. See [Streaming](/operations/streaming).

</Info>

## What You Need

1. A file per table under `extensionsPath` (default `lib/src/extensions`, set in [`zonai.yaml`](/configuration/zonai-yaml)). Subdirectories are searched too.
2. In it, a class extending `Extension<Row>` whose constructor passes the table to `super`, and a top-level `main()` returning an instance.
3. `zonai serve` (or `zonai dev`) running. It compiles the extensions worker and recompiles when a file under `extensionsPath` changes. `zonai compile` compiles it without serving.

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

All hooks default to no-ops (except the auth hooks that send [default emails](#default-emails)). Only override what you need.

- **One extension per table.** With two extensions for the same table, every hook call fails with `Extensions already registered for <table>`, so every create, update, delete and auth request fails too.
- **Extensions are optional.** Tables without one skip hooks. A project with no extension files at all still compiles; the server logs `No extensions detected` and runs no hooks.
- **Compiling runs `dart analyze` over `extensionsPath` first.** A single analyzer error stops the extensions worker from compiling.

## Where Hooks Run

For a create, the order is:

```text
rate limit → table rules → row rules → beforeCreate → INSERT → afterCreateSuccess → queued side effects
                                                          ↓ (INSERT failed)
                                                    afterCreateError
```

Update and delete follow the same shape with their own hooks. Hooks run **once per row**: `POST /db/many` calls `beforeCreate` for each object, and a delete that matches ten rows calls `beforeDelete` and `afterDeleteSuccess` ten times.

**Throwing from a `before*` hook aborts the request.** Nothing is written, and any side effects the hook queued are discarded. The client gets a server error (`500`), not your exception message. `beforeSignUp` is the one hook with a refusal the client can read; see [Declining a sign-up](/extensions/auth-hooks#declining-a-sign-up).

**Throwing from an `after*Success` hook fails the request after the write has committed.** The row is already saved, but the client sees an error, and the side effects that hook queued never run. Keep after-hooks from throwing unless a failed response is really what you want.

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

`jwt` is the caller's token, or `null` for an unauthenticated request. `afterUpdateSuccess` receives **two** rows: the row **before** the update and the row **after**.

One more hook has no request behind it:

| Hook | When It Runs |
|------|-------------|
| `onPushRejected(T row, String token, PushRejectionReason reason, Jwt? jwt)` | A push service permanently rejected a device token stored on this table, before Zonai prunes it |

See [Dead Tokens](/push/dead-tokens#the-hook).

## Auth Hooks

Mix in `AuthExtension` for auth table hooks:

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserExtensions extends Extension<User>
    with AuthExtension<User> {
  UserExtensions() : super(users);

  @override
  Future<void> onSignUp(User user, Jwt? jwt) async {
    email.send.verifyEmail(
      EmailAddress(address: user.email),
      table: 'users',
    );
  }
}
```

Auth hooks: `beforeSignUp`, `onSignUp`, `onSignIn`, `onRefresh`, `onLogout`, `onPasswordReset` and `onExternalAuthFirstSeen`. See [Auth Hooks](/extensions/auth-hooks).

## Default Emails

Two auth hooks send an email by default when the auth table has an email column (password, OTP, magic-link and OAuth tables all do):

| Hook       | Default email     |
| ---------- | ----------------- |
| `onSignUp` | Verify-email link |
| `onSignIn` | Login notice (not implemented yet: nothing is sent and the server logs an error) |

Overriding the hook replaces the default. Call `super.onSignUp(user, jwt)` from your override to keep the verify-email link. Override `onSignIn` to silence the login-notice error. All other hooks send nothing unless you call [`email.send`](/extensions/side-effects-email).

## Side Effects API

Inside any hook you have access to:

- `get`: read rows from any table (awaited, runs immediately)
- `mutate`: queue additional writes (run after the request's own write)
- `email`: send transactional email
- `push`: send a push notification to a queried set of devices
- `logger`: write to the server log

Every one of them acts as the hook's `jwt`; `get` also accepts an explicit `jwt:` to read as someone else. The same globals are available in [cron jobs](/cron-jobs/side-effects), where they act as `CronJwt`.

Queued writes can fire more hooks, which can queue more writes. Zonai stops after **10 rounds** of this and drops whatever is still queued; see [The Chain Limit](/extensions/side-effects-mutate#the-chain-limit). `push` is the odd one out: it is awaited, returns a job id, and its fan-out keeps running after the request finishes.

## Related

- [Create Hooks](/extensions/create-hooks)
- [Update Hooks](/extensions/update-hooks)
- [Delete Hooks](/extensions/delete-hooks)
- [Auth Hooks](/extensions/auth-hooks)
- [Side Effects: get](/extensions/side-effects-get)
- [Side Effects: mutate](/extensions/side-effects-mutate)
- [Side Effects: push](/extensions/side-effects-push)
- [Side Effects: email](/extensions/side-effects-email)
