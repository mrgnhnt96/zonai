# Access rules

Zonai enforces authorization through **rules**: Dart classes that decide whether a caller may perform an operation on a collection or on a specific record. Rules run **before** SQL is generated or executed. If a rule returns `false`, the server rejects the request with a permissions error and no database mutation occurs.

Rules are defined under your project’s **`rulesPath`** (default `lib/src/rules`, overridable in `zonai.yaml`). They are compiled into the `db_rules` worker executable alongside config, extensions, operations, and rate limits.

## How it works

1. An HTTP or auth handler receives a request (for example `POST /db` on `items`).
2. The server sends a **rule request** to the compiled `db_rules` worker, including the collection name, operation, optional record data, and the caller’s JWT (if any).
3. The worker evaluates your Dart rule classes and returns `canAccess` / `canPerform`.
4. If allowed, the server continues to rate limiting, operations (SQL generation), and query execution.

While `serve` is running, changes under `rulesPath` trigger a recompile so authorization stays in sync with your Dart code without restarting the database.

## Two levels: collection and record

Every user-facing collection typically needs **two** rule files:

| Level      | Class                                     | Question answered                                                |
| ---------- | ----------------------------------------- | ---------------------------------------------------------------- |
| Collection | `CollectionRules` / `AuthCollectionRules` | Can this caller perform this operation on the collection at all? |
| Record     | `RecordRules` / `AuthRecordRules`         | Can this caller perform this operation on **this row**?          |

The server checks **collection rules first**, then **record rules** when a specific row is involved.

| API flow                       | Collection check          | Record check                        |
| ------------------------------ | ------------------------- | ----------------------------------- |
| `create`                       | `canCreate`               | `canCreate` (with the payload row)  |
| `update` / `delete`            | `canUpdate` / `canDelete` | `canUpdate` / `canDelete` (per row) |
| `view` (single record)         | `canView`                 | `canView`                           |
| `list` / `count` / stream-list | `canList`                 | `canView` on **each** returned row  |

For **list** endpoints, every row in the result must pass record-level `canView`. If any row fails, the entire request fails. Design collection-level `canList` and record-level `canView` together, or use query filters so the database only returns rows the caller may see.

Auth endpoints use separate auth rule methods (see [Auth collections](#auth-collections)).

## Project layout

Default directory (override with `rulesPath` in `zonai.yaml`):

```text
lib/src/rules/
  item_collection_rules.dart
  item_record_rules.dart
  user_collection_rules.dart
  user_record_rules.dart
```

Each `.dart` file must export a **`main()`** that returns a **`Rules`** instance:

```dart
import 'package:my_app/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemCollectionRules main() => ItemCollectionRules();

final class ItemCollectionRules extends CollectionRules<ItemCollection, Item> {
  ItemCollectionRules() : super(items);

  @override
  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canView(Jwt? jwt) async => true;
}
```

```dart
import 'package:my_app/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

ItemRecordRules main() => ItemRecordRules();

class ItemRecordRules extends RecordRules<ItemCollection, Item> {
  ItemRecordRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt, Item record) async => true;
}
```

Only files with a `.dart` extension under `rulesPath` are included. If the directory is missing or empty, the worker still compiles with **built-in internal table rules** only (see [Internal tables](#internal-tables)).

Define **one rules file per class per collection** — one collection-rules file and one record-rules file. Each file’s `main()` must return a non-null `Rules`. If two files of the same kind target the same table name, the last one loaded wins.

## Base classes

| Collection type    | Collection rules            | Record rules            |
| ------------------ | --------------------------- | ----------------------- |
| Regular collection | `CollectionRules<S, R>`     | `RecordRules<S, R>`     |
| Auth collection    | `AuthCollectionRules<S, R>` | `AuthRecordRules<S, R>` |

Both are parameterized by your **schema** (`S`) and **row type** (`R`). Pass the schema getter (for example `items`, `users`) to the superclass constructor.

### Default behavior

If you do not override a method, the base classes **deny public access** and only allow admin tokens:

| Method (collection) | Default allows                   |
| ------------------- | -------------------------------- |
| `canCreate`         | JWT with `admin.canEdit == true` |
| `canUpdate`         | JWT with `admin.canEdit == true` |
| `canDelete`         | JWT with `admin.canEdit == true` |
| `canView`           | JWT with `admin.isAdmin == true` |
| `canList`           | JWT with `admin.isAdmin == true` |

| Method (record) | Default allows                   |
| --------------- | -------------------------------- |
| `canCreate`     | JWT with `admin.isAdmin == true` |
| `canUpdate`     | JWT with `admin.canEdit == true` |
| `canDelete`     | JWT with `admin.canEdit == true` |
| `canView`       | JWT with `admin.isAdmin == true` |

Unauthenticated callers (`jwt == null`) are denied unless you override a method to return `true`.

### Missing rules

If no rules are registered for a collection, collection-level checks **deny** access. If collection rules exist but record rules do not, record-level checks **deny** access. Add both files for each collection you expose through the API.

## The JWT argument

Rule methods receive an optional **`Jwt?`**. When the client sends a valid bearer token, the server verifies it and passes the decoded JWT; otherwise `jwt` is `null`.

Useful fields:

| Field               | Purpose                                                             |
| ------------------- | ------------------------------------------------------------------- |
| `jwt.userId`        | ID of the authenticated user (matches the auth collection row `id`) |
| `jwt.collection`    | Auth collection this token belongs to                               |
| `jwt.claims`        | Custom claims from `AuthOperations.addClaims`                       |
| `jwt.user`          | Snapshot of the user row at token issuance                          |
| `jwt.admin.isAdmin` | Admin UI / elevated read access                                     |
| `jwt.admin.canEdit` | Admin write access (create, update, delete)                         |

Example — only the owner may update a row:

```dart
@override
Future<bool> canUpdate(Jwt? jwt, Item record) async {
  if (jwt?.admin.canEdit case true) return true;
  return jwt?.userId.value == record.ownerId.value;
}
```

## Collection rule methods

Override the methods that correspond to operations your API uses. Each returns `Future<bool>`.

| Method      | `CollectionOperation` | Typical HTTP use                   |
| ----------- | --------------------- | ---------------------------------- |
| `canCreate` | `create`              | `POST /db`                         |
| `canUpdate` | `update`              | `PATCH /db`, `PATCH /db/many`      |
| `canDelete` | `delete`              | `DELETE /db`, `DELETE /db/many`    |
| `canView`   | `view`                | `GET /db`, stream-one              |
| `canList`   | `list`                | `GET /db/list`, stream-list, count |

Collection rules currently evaluate only these standard operation names. Custom operation strings (handled by `CollectionOperations.custom`) are denied at the collection-rules layer until custom-operation rule support is added.

## Record rule methods

Record rules receive the **typed row** (built from request data via `Table.safeCreate`) so you can inspect column values:

| Method      | When called                                             |
| ----------- | ------------------------------------------------------- |
| `canCreate` | Before insert; row is the payload, not yet in the DB    |
| `canUpdate` | Before update; row reflects the target record           |
| `canDelete` | Before delete; row reflects the target record           |
| `canView`   | Before returning a single row or including it in a list |

You cannot create auth collection rows through the generic DB API (`canCreate` on auth collections throws). Use the auth API (`POST /auth/sign-up`, etc.) instead.

## Auth collections

Auth collections extend the base classes with sign-in and sign-up authorization.

### `AuthCollectionRules`

| Method            | Purpose                                                   |
| ----------------- | --------------------------------------------------------- |
| `canAuthenticate` | Whether auth is enabled for this collection and auth type |

Default: returns `true` for all auth types.

### `AuthRecordRules`

| Method             | Purpose                                             |
| ------------------ | --------------------------------------------------- |
| `canSignUp`        | New user registration (record not yet in DB)        |
| `canSignIn`        | Existing user sign-in                               |
| `canPasswordReset` | Password reset flow (password auth only by default) |

Defaults:

- **`canSignUp`** — allowed for admin tokens; otherwise allowed when the schema implements the matching auth mixin (`PasswordAuth`, `OtpAuth`, or `MagicLinkAuth`).
- **`canSignIn`** — allowed when the schema supports the requested auth type.
- **`canPasswordReset`** — allowed for password auth only.

Record CRUD defaults for auth collections allow users to view and modify **their own row** (`record.id` matches `jwt.userId`), plus admin overrides.

Minimal auth setup (defaults only):

```dart
final class UserCollectionRules extends AuthCollectionRules<UserCollection, User> {
  UserCollectionRules() : super(users);
}

class UserRecordRules extends AuthRecordRules<UserCollection, User> {
  UserRecordRules() : super(users);
}
```

## Internal tables

Framework-managed SQLite tables (`_jwt`, `_log`, `_rate_limit`, `_auth_challenges`, `_raindrop_migrations`, `_photos`) ship with built-in rules. They are **always** merged into the `db_rules` executable; you do not add files for them under `rulesPath` unless you are [overriding photo rules](#photos-collection-_photos).

For every internal table except `_photos`, collection rules deny create, update, delete, and view for non-admin callers. Internal record rules allow admin read access only. These tables are not exposed through the public DB API like your app collections.

The `_photos` table is different: it backs the photo upload API and ships with permissive defaults that you can replace with your own rules. See [Photos collection (`_photos`)](#photos-collection-_photos) below.

## Photos collection (`_photos`)

The `_photos` table stores metadata for uploaded images (file path, owner, target collection). It is managed by Zonai and accessed through the **photo HTTP API** (`GET`, `POST`, `PATCH`, `DELETE` on `/photos`), not through generic `GET /db/list` on `_photos`.

Each photo request runs the same rule pipeline as other operations: **collection rules first**, then **record rules** when a row is involved.

| Photo API operation           | Collection check | Record check                                  |
| ----------------------------- | ---------------- | --------------------------------------------- |
| Create (`POST /photos`)       | `canCreate`      | `canCreate` (payload row built before insert) |
| View (`GET /photos/:id`)      | `canView`        | `canView`                                     |
| Update (`PATCH /photos/:id`)  | `canUpdate`      | `canUpdate`                                   |
| Delete (`DELETE /photos/:id`) | `canDelete`      | `canDelete`                                   |

### Row shape

Rule methods receive a typed **`PhotoEntry`** from `package:zonai_schema/zonai_schema.dart`. Useful fields for authorization:

| Field                    | Purpose                                                                               |
| ------------------------ | ------------------------------------------------------------------------------------- |
| `record.id`              | Photo ID (`PhotoId`)                                                                  |
| `record.ownerId`         | Authenticated user at upload time (`jwt.userId` when a token was sent)                |
| `record.ownerCollection` | Auth collection name from the JWT                                                     |
| `record.collection`      | App collection the photo is attached to (from `PhotoCreateMeta.collection` on create) |
| `record.path`            | Relative path under the configured images directory                                   |
| `record.extension`       | Normalized file extension (`jpg`, `png`, etc.)                                        |

Pass the schema getter **`photos`** to your rule class constructors (same pattern as `items`, `users`, etc.).

### Built-in defaults

If you do not add override files, Zonai uses the built-in photo rules:

**Collection rules** — allow create, update, delete, and view for all callers (including unauthenticated).

**Record rules**:

| Method      | Default                                         |
| ----------- | ----------------------------------------------- |
| `canView`   | Allowed for everyone                            |
| `canCreate` | Requires a JWT (`jwt != null`)                  |
| `canUpdate` | Owner (`jwt.userId == record.ownerId`) or admin |
| `canDelete` | Owner or admin                                  |

### Overriding photo rules

Photo rules set `canBeOverridden: true`, so you can register your own **`CollectionRules`** and **`RecordRules`** for `_photos` under `rulesPath`. Add **both** files — one collection-rules file and one record-rules file — using the same layout as your app collections.

User rules are loaded **after** built-in internal rules and replace them for `_photos`. Other internal tables cannot be overridden; registering rules for them throws a duplicate-registration error when the rules worker loads.

Example — restrict uploads to signed-in users and reads to owners or admins:

```dart
// lib/src/rules/photo_collection_rules.dart
import 'package:zonai_schema/zonai_schema.dart';

PhotoCollectionRules main() => PhotoCollectionRules();

final class PhotoCollectionRules extends CollectionRules<PhotosCollection, PhotoEntry> {
  PhotoCollectionRules() : super(photos);

  @override
  Future<bool> canCreate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canDelete(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canView(Jwt? jwt) async => true;
}
```

```dart
// lib/src/rules/photo_record_rules.dart
import 'package:zonai_schema/zonai_schema.dart';

PhotoRecordRules main() => PhotoRecordRules();

final class PhotoRecordRules extends RecordRules<PhotosCollection, PhotoEntry> {
  PhotoRecordRules() : super(photos);

  @override
  Future<bool> canView(Jwt? jwt, PhotoEntry record) async {
    if (jwt?.admin.isAdmin case true) return true;
    return jwt?.userId == record.ownerId;
  }

  @override
  Future<bool> canCreate(Jwt? jwt, PhotoEntry record) async {
    if (jwt == null) return false;
    return jwt.userId == record.ownerId;
  }

  @override
  Future<bool> canUpdate(Jwt? jwt, PhotoEntry record) async {
    if (jwt?.admin.canEdit case true) return true;
    return jwt?.userId == record.ownerId;
  }

  @override
  Future<bool> canDelete(Jwt? jwt, PhotoEntry record) async {
    if (jwt?.admin.canEdit case true) return true;
    return jwt?.userId == record.ownerId;
  }
}
```

After adding or changing these files, recompile rules (`dart run zonai compile` or press **`c`** while `serve` is running).

## Compilation and analysis

When rules are compiled:

1. **`dart analyze`** runs on `rulesPath`. Compilation aborts if analysis fails.
2. **`RuleGenerator`** writes `.dart_tool/zonai/db_rules.dart`, importing every rules file plus internal rules, and wiring `DbRules(...).start()`.
3. **`dart compile exe`** produces `.zonai/executables/db_rules.exe` (path configurable via the Zonai data directory).

If the executable is missing at runtime, the server logs instructions to add files under `rulesPath` and run `zonai serve` or press **`c`** to recompile.

## Commands

From your app directory (where `zonai.yaml` lives):

```bash
# Compile all workers, including rules
dart run zonai compile

# Dev server: watches rulesPath and recompiles on change
dart run zonai serve
```

While `serve` is running, press **`c`** to recompile all workers (config, rules, extensions, operations, rate limits).

See also **[config-and-env-flavors.md](config-and-env-flavors.md)** for `--flavor` and env defines passed into worker executables.

## Configuration

`zonai.yaml`:

```yaml
rulesPath: lib/src/rules
```

## Minimal example

From `apps/playground/lib/src/rules/item_collection_rules.dart` and `item_record_rules.dart` — open access for development:

```dart
final class ItemCollectionRules extends CollectionRules<ItemCollection, Item> {
  ItemCollectionRules() : super(items);

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;
}
```

```dart
class ItemRecordRules extends RecordRules<ItemCollection, Item> {
  ItemRecordRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt, Item record) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Item record) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Item record) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Item record) async => true;
}
```

Tighten these overrides for production — the playground values are intentionally permissive.

## See also

- **[operations.md](operations.md)** — SQL generation for each operation (runs after rules pass)
- **[extensions.md](extensions.md)** — lifecycle hooks around mutations and auth (before/after SQL)
- **[rate-limiting.md](rate-limiting.md)** — per-operation request limits (separate worker, same compile flow)
- **[config-and-env-flavors.md](config-and-env-flavors.md)** — worker executables and compile-time env
- **`libs/zonai_schema/lib/src/rules/`** — base rule classes and auth defaults
