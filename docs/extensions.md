# Extensions

Zonai **extensions** are lifecycle hooks that run around database mutations and auth events. They let you run Dart code when records are created, updated, or deleted, or when users sign up, sign in, or log out — without putting that logic in HTTP handlers or SQL.

Extensions are defined under your project’s **`extensionsPath`** (default `lib/src/extensions`, overridable in `zonai.yaml`). At compile time, Zonai bundles your extension classes into the `db_extensions` worker executable.

Extensions do **not** replace [rules](rules.md) or [operations](operations.md). Rules decide *whether* a request is allowed; operations build SQL; extensions run *before or after* those steps to observe or react to changes.

## How it works

1. A client request passes [rules](rules.md) and [rate limits](rate-limiting.md).
2. For create, update, or delete, the server sends an **extension request** to the compiled `db_extensions` worker (for example `beforeCreate` on `items`).
3. Your extension class runs the matching hook method with a typed row and the caller’s JWT.
4. The server continues: operations generate SQL, SQLite executes the mutation, then **after-success** hooks run.
5. If the hook used `get`, `mutate`, or `email`, those side effects are queued and applied after the main transaction (with rules and extension hooks run again for each effect).

While `serve` is running, changes under `extensionsPath` trigger a recompile so hooks stay in sync with your Dart code without restarting the database.

## When hooks run

Extensions sit between authorization and persistence. The order for a **create** is:

```text
collection rules → record rules → beforeCreate → SQL insert → afterCreateSuccess
                                                      ↓ (on failure)
                                               afterCreateError
```

| Operation | Before SQL                         | After SQL success              | After SQL error        |
| --------- | ---------------------------------- | ------------------------------ | ---------------------- |
| Create    | `beforeCreate`                     | `afterCreateSuccess`           | `afterCreateError`     |
| Update    | `beforeUpdate`                     | `afterUpdateSuccess`           | `afterUpdateError`     |
| Delete    | `beforeDelete`                     | `afterDeleteSuccess`           | `afterDeleteError`     |

Update hooks receive the row **before** the patch is applied (`beforeUpdate`) and typed **before/after** rows on success (`afterUpdateSuccess`). Delete hooks receive the rows about to be removed.

Auth hooks run after the auth flow succeeds (JWT issued or session cleared):

| Hook       | When called                          |
| ---------- | ------------------------------------ |
| `onSignUp` | New user registered                  |
| `onSignIn` | Existing user signed in              |
| `onLogout` | User logged out                      |

For auth hooks, the **`jwt` argument is the caller making the request**, not necessarily the user row in `object`. On sign-up, `jwt` is typically `null`.

If no extension is registered for a collection, the worker returns immediately — hooks are optional per collection. The **`db_extensions` executable must still be compiled** before create, update, delete, or auth endpoints run; see [Compilation](#compilation-and-analysis).

Throwing from a **before** hook aborts the request. Throwing from an **after** hook fails the request after the database change has already committed.

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

class ItemExtensions extends Extension<Item>
    with CreateExtension, UpdateExtension, DeleteExtension {
  ItemExtensions() : super(items);
}
```

Only files with a `.dart` extension under `extensionsPath` are included. Define **one extension file per collection**. Each file’s `main()` must return a non-null `Extension`. If two files target the same table name, the last one loaded wins.

Unlike rules and operations, extensions have **no built-in internal handlers**. You need **at least one** extension file (even a no-op class) for the worker to compile. The **`extensionsPath` directory must exist** before `zonai compile` or `zonai serve` can build extensions.

## Base class and mixins

Extend **`Extension<R>`** with your row type `R` and pass the schema getter (for example `items`, `users`) to the superclass constructor.

Add only the mixins you need:

| Mixin            | Use for                                      |
| ---------------- | -------------------------------------------- |
| `CreateExtension` | Create hooks                                |
| `UpdateExtension` | Update hooks                                |
| `DeleteExtension` | Delete hooks                                |
| `AuthExtension`   | Sign-up, sign-in, logout hooks (auth collections) |

You can combine mixins on one class (for example `CreateExtension` + `UpdateExtension` + `DeleteExtension` on a regular collection, or add `AuthExtension` on a user collection).

### Default email behavior

Several hooks send email automatically when the schema implements **`HasEmail`**:

| Hook / method        | Default email (if collection has email) |
| -------------------- | --------------------------------------- |
| `afterCreateSuccess` | Login notice                            |
| `onSignUp`           | Verify-email link                       |
| `onSignIn`           | Login notice                            |

Override these methods to customize or disable the default. Call `email.send.*` helpers explicitly when you want different templates or timing.

## Hook methods

All hook methods are `async` and receive an optional **`Jwt?`** for the authenticated caller (when the client sent a valid bearer token).

### `CreateExtension`

| Method               | Arguments              | Purpose                                      |
| -------------------- | ---------------------- | -------------------------------------------- |
| `beforeCreate`       | `R object`, `Jwt? jwt` | Run before insert; throw to abort            |
| `afterCreateSuccess` | `R row`, `Jwt? jwt`    | Run after row is in the database             |
| `afterCreateError`   | `Object error`, `Jwt? jwt` | Run when insert fails                    |

### `UpdateExtension`

| Method               | Arguments                         | Purpose                           |
| -------------------- | --------------------------------- | --------------------------------- |
| `beforeUpdate`       | `R row`, `Jwt? jwt`               | Run before patch; throw to abort  |
| `afterUpdateSuccess` | `R before`, `R after`, `Jwt? jwt` | Run after successful update       |
| `afterUpdateError`   | `Object error`, `Jwt? jwt`        | Run when update fails             |

### `DeleteExtension`

| Method               | Arguments              | Purpose                           |
| -------------------- | ---------------------- | --------------------------------- |
| `beforeDelete`       | `R row`, `Jwt? jwt`    | Run before delete; throw to abort |
| `afterDeleteSuccess` | `R row`, `Jwt? jwt`    | Run after rows are removed        |
| `afterDeleteError`   | `Object error`, `Jwt? jwt` | Run when delete fails         |

### `AuthExtension`

| Method     | Arguments           | Purpose                    |
| ---------- | ------------------- | -------------------------- |
| `onSignUp` | `R user`, `Jwt? jwt`| After successful sign-up   |
| `onSignIn` | `R user`, `Jwt? jwt`| After successful sign-in   |
| `onLogout` | `R user`, `Jwt? jwt`| After logout               |

## Side effects: `get`, `mutate`, and `email`

Inside the extension worker, Zonai exposes globals (from `package:zonai_schema/zonai_schema.dart`) that talk back to the server:

| Global   | Purpose                                                                 |
| -------- | ----------------------------------------------------------------------- |
| `get`    | Read rows (`get.one`, `get.many`) with the same rules as the public API |
| `mutate` | Queue creates, updates, or deletes (`mutate.create`, `mutate.update`, `mutate.delete`) |
| `email`  | Send custom or built-in transactional email                               |
| `logger` | Log at debug/info/warn/error (forwarded to the server console)          |

**Reads** (`get`) run immediately and respect collection/record rules for the JWT passed to the hook.

**Writes** (`mutate`) are **queued** as side effects. They run after the main mutation commits, in a separate transaction. Each side effect goes through rules and extension hooks again (up to 10 chained iterations). Use this to update related rows or send follow-up work without blocking the original SQL.

Example — after create, read the row back and patch a column:

```dart
@override
Future<void> afterCreateSuccess(Item object, Jwt? jwt) async {
  final item = await get.one(collection: 'items', where: Eq('id', object.id));
  if (item == null) return;

  mutate.update.one(
    collection: 'items',
    updates: [Update.column('body', .literal('Updated by extension'))],
    where: Eq('id', object.id),
  );
}
```

Built-in email helpers on `email.send`:

| Method              | Purpose              |
| ------------------- | -------------------- |
| `verifyEmail`       | Email verification   |
| `loginNotice`       | Login notification   |
| `passwordReset`     | Password reset link  |
| `magicLink`         | Magic-link sign-in   |
| `optCode`           | OTP code             |
| `confirmEmailChange`| Email change confirm |

Pass `collection:` and optional `variables:` for template substitution.

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

While `serve` is running, press **`c`** to recompile all workers (config, rules, extensions, operations, rate limits).

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

class ItemExtensions extends Extension<Item>
    with CreateExtension, UpdateExtension, DeleteExtension {
  ItemExtensions() : super(items);

  @override
  Future<void> beforeCreate(Item object, Jwt? jwt) async {
    logger.debug('EXTENSION beforeCreate');
  }

  @override
  Future<void> afterCreateSuccess(Item object, Jwt? jwt) async {
    mutate.update.one(
      collection: 'items',
      updates: [Update.column('body', .literal('Something else!!!'))],
      where: Eq('id', object.id),
    );
  }
}
```

For auth collections, mix in `AuthExtension` and override `onSignUp`, `onSignIn`, or `onLogout` as needed.

## See also

- **[rules.md](rules.md)** — authorization (checked before extension hooks)
- **[operations.md](operations.md)** — SQL generation (runs after before-hooks)
- **[rate-limiting.md](rate-limiting.md)** — per-operation request limits
- **[config-and-env-flavors.md](config-and-env-flavors.md)** — worker executables and compile-time env
- **`libs/zonai_schema/lib/src/extension.dart`** — base class and mixin defaults
