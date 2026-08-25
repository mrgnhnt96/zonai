# Extensions

Zonai **extensions** are lifecycle hooks that run around database mutations and auth events. They let you run Dart code when records are created, updated, or deleted, or when users sign up, sign in, refresh their session, or log out — without putting that logic in HTTP handlers or SQL.

Extensions are defined under your project’s **`extensionsPath`** (default `lib/src/extensions`, overridable in `zonai.yaml`). At compile time, Zonai bundles your extension classes into the `db_extensions` worker executable.

Extensions do **not** replace [rules](rules.md) or [operations](operations.md). Rules decide _whether_ a request is allowed; operations build SQL; extensions run _before or after_ those steps to observe or react to changes.

## How it works

1. A client request passes [rules](rules.md) and [rate limits](rate-limiting.md).
2. For create, update, or delete, the server sends an **extension request** to the compiled `db_extensions` worker (for example `beforeCreate` on `items`).
3. Your extension class runs the matching hook method with a typed row and the caller’s JWT.
4. The server continues: operations generate SQL, SQLite executes the mutation, then **after-success** hooks run.
5. If the hook used `get`, `mutate`, or `email`, those side effects are queued and applied after the main transaction (with rules and extension hooks run again for each effect). `push` is the exception: it is awaited, and its fan-out outlives the request entirely.

While `serve` is running, changes under `extensionsPath` trigger a recompile so hooks stay in sync with your Dart code without restarting the database.

## When hooks run

Extensions sit between authorization and persistence. The order for a **create** is:

```text
collection rules → row rules → beforeCreate → SQL insert → afterCreateSuccess
                                                      ↓ (on failure)
                                               afterCreateError
```

A **sign-up** is the same shape, with its own pair — the JWT is minted between
them, so `beforeSignUp` is the last point at which there is nothing to undo:

```text
collection rules → row rules → beforeSignUp → SQL insert → mint JWT → onSignUp
```

| Operation | Before SQL     | After SQL success    | After SQL error    |
| --------- | -------------- | -------------------- | ------------------ |
| Create    | `beforeCreate` | `afterCreateSuccess` | `afterCreateError` |
| Update    | `beforeUpdate` | `afterUpdateSuccess` | `afterUpdateError` |
| Delete    | `beforeDelete` | `afterDeleteSuccess` | `afterDeleteError` |

Update hooks receive the row **before** the patch is applied (`beforeUpdate`) and typed **before/after** rows on success (`afterUpdateSuccess`). Delete hooks receive the rows about to be removed.

One hook has no operation of its own, because nothing the app did triggers it:

| Hook              | When called                                                    |
| ----------------- | -------------------------------------------------------------- |
| `onPushRejected`  | FCM permanently rejected a device token on this collection      |

It fires from a push fan-out rather than a request, **before** Zonai prunes the token, and under every `onPermanentRejection` setting including `none`. See [push.md](push.md).

Auth hooks run after the auth flow succeeds (JWT issued or session cleared) — all but one:

| Hook           | When called                              |
| -------------- | ---------------------------------------- |
| `beforeSignUp` | A new user is **about to be** registered |
| `onSignUp`     | New user registered                      |
| `onSignIn`     | Existing user signed in                  |
| `onRefresh`    | Session token refreshed                  |
| `onLogout`     | User logged out                          |

`beforeSignUp` is the exception, and it is the only auth hook that can change the outcome — see [Declining a sign-up](#declining-a-sign-up).

For auth hooks, the **`jwt` argument is the caller making the request**, not necessarily the user row in `object`. On sign-up, `jwt` is typically `null`.

If no extension is registered for a collection, the worker returns immediately — hooks are optional per collection. The **`db_extensions` executable must still be compiled** before create, update, delete, or auth endpoints run; see [Compilation](#compilation-and-analysis).

Throwing from a **before** hook aborts the request. Throwing from an **after** hook fails the request after the database change has already committed.

## Declining a sign-up

`beforeSignUp` runs before the row is inserted. Throw `SignUpDeclinedException`
from it and the caller is answered **403** with the reason you chose:

```dart in:extension-user
@override
Future<void> beforeSignUp(SignUpCandidate candidate, Jwt? jwt) async {
  if (!candidate.email.endsWith('@acme.com')) {
    throw const SignUpDeclinedException('Sign-up is limited to Acme staff');
  }
}
```

```json
{ "error": "Sign-up is limited to Acme staff" }
```

The reason is rendered to the caller **verbatim**, unlike the generic
`Forbidden` most 403s carry — the hook exists to tell someone why, so put
nothing in it they should not see.

Nothing is left behind to undo: no row, no session, and no verify-email. Any
other exception aborts the sign-up too, but as a `500` — declining is the
deliberate path, and a hook that merely crashed should not look like a refusal.

### What it does and does not cover

`candidate` is a `SignUpCandidate` — the sign-up **request** — and not the
app's row class, which is the one place `beforeSignUp` differs from every
other hook. There is no row yet, so there is nothing typed to hand over:

| Field       | What it is                                                     |
| ----------- | -------------------------------------------------------------- |
| `email`     | The address the sign-up was made with                          |
| `object`    | The extra columns the body carried, as the client sent them    |
| `table`     | The auth collection being signed up into                       |

`candidate['nickname']` is shorthand for `candidate.object['nickname']`.

Nothing in `object` has been through rules or the insert yet — that is the
point of being here — so do not treat a value in it as the value the row will
end up with. The address is deliberately *not* duplicated into `object`: an
auth table names its own email column, so there is no key that would be right
for every project.

It runs on the three flows that insert an auth row directly: **password**,
**OTP** and **magic-link** sign-up.

It does **not** run for a first-seen OAuth or external-IdP identity. Those
provision through [`onExternalAuthFirstSeen`](external-idp.md#refusing-to-provision),
which receives verified IdP claims rather than a candidate row, and which
declines by returning without inserting one.

Note that path answers **401**, not 403 — there is no thrown refusal to carry a
reason. The 403-with-your-own-message equivalent over there is the provisioning
gate; see [Refusing to provision](external-idp.md#refusing-to-provision).

### It runs before the email, and it can run twice

For OTP and magic link the account is created when the **code is verified**,
not when it is requested. So the hook runs at *both* points: once when the
code is requested, before anything is sent, and again at verify, immediately
before the row is inserted.

That makes it **at least once** for these two flows, and a hook body with a
side effect has to tolerate running twice for a single sign-up. Keeping the
verify-time call is deliberate: a challenge is valid for ten minutes, and the
answer your hook would give can change inside that window.

The password flow requests and inserts in one call, so the hook runs once
there.

> Earlier versions ran the hook only at the insert. On OTP and magic link that
> meant the code email had already been sent by the time the app refused — the
> hook prevented the account but not the mail. It now runs before the send.

## Project layout

Default directory (override with `extensionsPath` in `zonai.yaml`):

```text
lib/src/extensions/
  item_extensions.dart
  user_extensions.dart
```

Each `.dart` file must export a **`main()`** that returns an **`Extension`** instance for one collection:

```dart
import 'package:my_app/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemExtensions main() => ItemExtensions();

class ItemExtensions extends Extension<Item> {
  ItemExtensions() : super(items);
}
```

Only files with a `.dart` extension under `extensionsPath` are included. Define **one extension file per collection**. Each file’s `main()` must return a non-null `Extension`. If two files target the same table name, the last one loaded wins.

Unlike rules and operations, extensions have **no built-in internal handlers**. You need **at least one** extension file (even a no-op class) for the worker to compile. The **`extensionsPath` directory must exist** before `zonai build`, `zonai compile`, or `zonai serve` can build extensions.

## Base class and mixins

Extend **`Extension<R>`** with your row type `R` and pass the schema getter (for example `items`, `users`) to the superclass constructor.

The create, update and delete hooks are methods on `Extension<R>` itself, each
defaulting to a no-op — override the ones you want and leave the rest alone.
There is no mixin to opt into them:

| Hook group | Methods                                                              |
| ---------- | -------------------------------------------------------------------- |
| Create     | `beforeCreate`, `afterCreateSuccess`, `afterCreateError`             |
| Update     | `beforeUpdate`, `afterUpdateSuccess`, `afterUpdateError`             |
| Delete     | `beforeDelete`, `afterDeleteSuccess`, `afterDeleteError`             |

**`AuthExtension<R>`** is the one mixin, and it applies only to auth
collections. It takes a single type argument — the row type, the same one you
gave `Extension` — and adds `onSignUp`, `onSignIn`, `onRefresh`, `onLogout`,
`onPasswordReset` and `onExternalAuthFirstSeen`:

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

class UserExtensions extends Extension<User> with AuthExtension<User> {
  UserExtensions() : super(users);
}
```

Every hook takes a trailing `Jwt? jwt` — the caller's token, or `null` when the
request is unauthenticated.

### Default email behavior

Several hooks send email automatically when the schema implements **`HasEmail`**. For SMTP setup, template files, and variable reference, see **[email.md](email.md)**; for getting a real provider and domain delivering that mail, see **[sending-email.md](sending-email.md)**.

| Hook / method        | Default email (if collection has email) |
| -------------------- | --------------------------------------- |
| `afterCreateSuccess` | Login notice                            |
| `onSignUp`           | Verify-email link                       |
| `onSignIn`           | Login notice                            |

Override these methods to customize or disable the default. Call `email.send.*` helpers explicitly when you want different templates or timing.

## Hook methods

All hook methods are `async` and receive an optional **`Jwt?`** for the authenticated caller (when the client sent a valid bearer token).

### `CreateExtension`

| Method               | Arguments                  | Purpose                           |
| -------------------- | -------------------------- | --------------------------------- |
| `beforeCreate`       | `R object`, `Jwt? jwt`     | Run before insert; throw to abort |
| `afterCreateSuccess` | `R row`, `Jwt? jwt`        | Run after row is in the database  |
| `afterCreateError`   | `Object error`, `Jwt? jwt` | Run when insert fails             |

### `UpdateExtension`

| Method               | Arguments                         | Purpose                          |
| -------------------- | --------------------------------- | -------------------------------- |
| `beforeUpdate`       | `R row`, `Jwt? jwt`               | Run before patch; throw to abort |
| `afterUpdateSuccess` | `R before`, `R after`, `Jwt? jwt` | Run after successful update      |
| `afterUpdateError`   | `Object error`, `Jwt? jwt`        | Run when update fails            |

### `DeleteExtension`

| Method               | Arguments                  | Purpose                           |
| -------------------- | -------------------------- | --------------------------------- |
| `beforeDelete`       | `R row`, `Jwt? jwt`        | Run before delete; throw to abort |
| `afterDeleteSuccess` | `R row`, `Jwt? jwt`        | Run after rows are removed        |
| `afterDeleteError`   | `Object error`, `Jwt? jwt` | Run when delete fails             |

### `onPushRejected`

| Method           | Arguments                                                            | Purpose                                     |
| ---------------- | -------------------------------------------------------------------- | ------------------------------------------- |
| `onPushRejected` | `R row`, `String token`, `PushRejectionReason reason`, `Jwt? jwt`    | A device token is dead; runs before pruning |

`row` is the **unmodified** row: under `clearColumn` the token has not been
nulled yet, and under `deleteRow` the row still exists. Only permanent
rejections reach here — a timeout is counted on the job and never pruned.
Throwing is logged and does not stop the prune or the fan-out.

### `AuthExtension`

| Method         | Arguments                 | Purpose                                                     |
| -------------- | ------------------------- | ----------------------------------------------------------- |
| `beforeSignUp` | `SignUpCandidate candidate`, `Jwt? jwt` | Before the row is inserted; throw to decline   |
| `onSignUp`     | `R user`, `Jwt? jwt`      | After successful sign-up                                    |
| `onSignIn`  | `R user`, `Jwt? jwt` | After successful sign-in                                    |
| `onRefresh` | `R user`, `Jwt? jwt` | After a new access token is issued via `POST /auth/refresh` |
| `onLogout`  | `R user`, `Jwt? jwt` | After logout                                                |

## Side effects: `get`, `mutate`, `email`, and `push`

Inside the extension worker, Zonai exposes globals (from `package:zonai_schema/zonai_schema.dart`) that talk back to the server:

| Global   | Purpose                                                                                |
| -------- | -------------------------------------------------------------------------------------- |
| `get`    | Read rows (`get.one`, `get.many`) with the same rules as the public API                |
| `mutate` | Queue creates, updates, or deletes (`mutate.create`, `mutate.update`, `mutate.delete`) |
| `email`  | Send custom or built-in transactional email                                            |
| `push`   | Send a push notification to a queried set of devices; see [push.md](push.md)           |
| `logger` | Log at debug/info/warn/error (forwarded to the server console)                         |

The same globals are available inside [cron](cron.md) `run()` methods (using `CronJwt` instead of the caller’s session token).

**Reads** (`get`) run immediately and respect collection/row rules for the JWT passed to the hook.

**`push`** is the one that does not fit either shape above. It is awaited and returns a `PushJobId`, but the wait is for the job to be *recorded*, not sent — the fan-out runs on the host afterwards and outlives the request. Call it from `after*` hooks only: a `before` hook runs prior to the write, and a notification announcing something that may not happen cannot be recalled.

**Writes** (`mutate`) are **queued** as side effects. They run after the main mutation commits, in a separate transaction. Each side effect goes through rules and extension hooks again (up to 10 chained iterations). Use this to update related rows or send follow-up work without blocking the original SQL.

Example — after create, read the row back and patch a column:

```dart in:extension-item
@override
Future<void> afterCreateSuccess(Item object, Jwt? jwt) async {
  final item = await get.one(tableName: 'items', where: Eq('id', object.id));
  if (item == null) return;

  mutate.update.one(
    table: 'items',
    updates: [Update.column('body', .literal('Updated by extension'))],
    where: Eq('id', object.id),
  );
}
```

Built-in email helpers on `email.send`:

| Method               | Purpose              |
| -------------------- | -------------------- |
| `verifyEmail`        | Email verification   |
| `loginNotice`        | Login notification   |
| `passwordReset`      | Password reset link  |
| `magicLink`          | Magic-link sign-in   |
| `optCode`            | OTP code             |
| `confirmEmailChange` | Email change confirm |

Pass `collection:` and optional `variables:` for template substitution. See **[email.md](email.md)** for built-in template variables and custom `Email` sends.

## Compilation and analysis

When extensions are compiled:

1. **`dart analyze`** runs on `extensionsPath`. Compilation aborts if analysis fails.
2. **`ExtensionGenerator`** writes `.dart_tool/zonai/db_extensions.dart`, importing every extension file and wiring `DbExtensions(...).start()`.
3. **`dart compile exe`** produces `.zonai/executables/db_extensions.exe` (path configurable via the Zonai data directory).

If the executable is missing at runtime, create `extensionsPath`, add at least one `.dart` extension file, and run `zonai serve` or press **`c`** to recompile.

## Commands

From your app directory (where `zonai.yaml` lives):

```bash
# Compile all workers, including extensions
dart run zonai compile

# Dev server: watches extensionsPath and recompiles on change
dart run zonai serve
```

While `serve` is running, press **`c`** to recompile all workers (config, rules, extensions, operations, rate limits, crons).

See also **[config-and-env-flavors.md](config-and-env-flavors.md)** for `--flavor` and env defines passed into worker executables.

## Configuration

`zonai.yaml`:

```yaml
extensionsPath: lib/src/extensions
```

## Example

From `apps/playground/lib/src/extensions/item_extensions.dart` — hooks on the `items` collection with a side-effect update after create:

```dart
import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemExtensions main() => ItemExtensions();

class ItemExtensions extends Extension<Item> {
  ItemExtensions() : super(items);

  @override
  Future<void> beforeCreate(Item object, Jwt? jwt) async {
    logger.debug('EXTENSION beforeCreate');
  }

  @override
  Future<void> afterCreateSuccess(Item object, Jwt? jwt) async {
    mutate.update.one(
      table: 'items',
      updates: [Update.column('body', .literal('Something else!!!'))],
      where: Eq('id', object.id),
    );
  }
}
```

For auth collections, mix in `AuthExtension<R>` and override `onSignUp`, `onSignIn`, `onRefresh`, or `onLogout` as needed.

## See also

- **[auth.md](auth.md)** — session tokens and the refresh endpoint
- **[rules.md](rules.md)** — authorization (checked before extension hooks)
- **[operations.md](operations.md)** — SQL generation (runs after before-hooks)
- **[rate-limiting.md](rate-limiting.md)** — per-operation request limits
- **[cron.md](cron.md)** — scheduled background jobs
- **[push.md](push.md)** — push notifications, and the `onPushRejected` hook
- **[config-and-env-flavors.md](config-and-env-flavors.md)** — worker executables and compile-time env
- **`libs/zonai_schema/lib/src/extension.dart`** — base class and mixin defaults
