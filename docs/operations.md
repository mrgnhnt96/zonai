# Collection operations

Zonai turns HTTP and auth requests into SQL through **collection operations**: Dart classes that describe how each table is read and written. Your app defines one operations file per collection under **`operationsPath`** (default `lib/src/operations`, overridable in `zonai.yaml`). At compile time, Zonai bundles those files with built-in internal-table operations into the `db_operations` worker executable.

Operations do **not** run queries themselves. The server sends a structured request to the worker; the worker returns SQL and bound values; the server executes that SQL against SQLite after rules and rate limits have been checked.

## How it works

1. An HTTP or auth handler needs SQL for a collection (for example `create` on `items`).
2. The server sends an **operation request** to the compiled `db_operations` worker.
3. The worker finds the matching `CollectionOperations` instance (keyed by table name) and builds a Raindrop query.
4. The worker translates the query to SQL for the configured dialect (SQLite by default) and returns it.
5. The server runs the SQL on the database and returns the result to the client.

While `serve` is running, changes under `operationsPath` trigger a recompile so SQL generation stays in sync with your Dart code without restarting the database.

## Project layout

Default directory (override with `operationsPath` in `zonai.yaml`):

```text
lib/src/operations/
  item_operations.dart
  user_operations.dart
  post_operations.dart
```

Each `.dart` file must export a **`main()`** that returns a **`CollectionOperations`** instance for one collection:

```dart
import 'package:my_app/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class ItemOperations extends CollectionOperations<ItemCollection, Item> {
  ItemOperations() : super(items);
}

ItemOperations main() => ItemOperations();
```

Only files with a `.dart` extension under `operationsPath` are included. If the directory is missing or empty, the worker still compiles with **built-in internal table operations** only (see [Internal tables](#internal-tables)).

Define **one operations file per collection**. Each file’s `main()` must return a non-null `CollectionOperations`. If two files target the same table name, the last one loaded wins.

## Base classes

| Collection type    | Extend / mix in                                 | Example                         |
| ------------------ | ----------------------------------------------- | ------------------------------- |
| Regular collection | `CollectionOperations<S, R>`                    | Items, posts, companies         |
| Auth collection    | `CollectionOperations<S, R>` + `AuthOperations` | Users with sign-in / JWT claims |

`CollectionOperations` is parameterized by your **schema** (`S`) and **row type** (`R`). Pass the schema getter (for example `items`, `users`) to the superclass constructor.

### Auth collections

Auth collections mix in **`AuthOperations`** to customize JWT claims and auth email link settings:

```dart
final class UserOperations extends CollectionOperations<UserCollection, User>
    with AuthOperations {
  UserOperations() : super(users);

  @override
  Future<Claims> addClaims({required Jwt jwt}) async {
    return Claims({'is_awesome': true});
  }
}

UserOperations main() => UserOperations();
```

| Method                | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `addClaims`           | Extra JWT claims merged into tokens for this collection                 |
| `magicLinkConfig`     | Magic-link path and expiry (default `/auth/magic-link`, 10 minutes)     |
| `resetPasswordConfig` | Reset-password path and expiry (default `/auth/reset-password`, 10 min) |
| `verifyEmailConfig`   | Verify-email path and expiry (default `/auth/verify-email`, 24 hours)   |

The framework also uses operations for auth-specific SQL (lookup by email, sign-up row shape, column name resolution for password/email/id fields). You normally only override the methods above unless you need custom query behavior via the standard CRUD helpers.

## Built-in query helpers

`CollectionOperations` exposes Raindrop builders for the operations the API uses. Override a method when you need different SQL; otherwise the defaults apply.

| Method       | Used for                                              |
| ------------ | ----------------------------------------------------- |
| `insert`     | Create one row from a map                             |
| `insertMany` | Bulk insert typed rows                                |
| `update`     | Patch rows matching a `Where` clause                  |
| `delete`     | Delete rows matching a `Where` clause                 |
| `list`       | Select with optional filter, limit, offset, `groupBy` |
| `count`      | Count rows with optional filter                       |
| `custom`     | Non-standard operation names (override required)      |

Builders are awaitable or can be chained further before awaiting. Inserts use `.returning()` so the server can read created rows.

### Standard operations and HTTP

These map to `CollectionOperation` names in rules and rate limiting:

| Operation | Operations helper | Typical HTTP use                |
| --------- | ----------------- | ------------------------------- |
| `create`  | `insert`          | `POST /db`                      |
| `update`  | `update`          | `PATCH /db`, `PATCH /db/many`   |
| `delete`  | `delete`          | `DELETE /db`, `DELETE /db/many` |
| `view`    | `list` (limit 1)  | `GET /db`, stream-one           |
| `list`    | `list`            | `GET /db/list`, stream-list     |
| `count`   | `count`           | `GET /db/count`                 |

Any other operation string is treated as a **custom operation** and routed to `custom()`.

### Update behavior

`update` accepts a list of `Update` values:

- **`Update.column(name, value)`** — set one column, including dotted paths for nested JSON map keys (for example `profile.displayName`).
- **`Update.object(map)`** — set multiple columns from a map; nested `UpdateValue` JSON in the map is interpreted the same as column updates.

`UpdateValue` variants:

| Value       | Effect on scalar columns | Effect on list columns (`ListTransformer`) |
| ----------- | ------------------------ | ------------------------------------------ |
| `literal`   | Set to value             | Set to value                               |
| `increment` | `column + 1`             | Not supported on JSON map columns          |
| `decrement` | `column - 1`             | Not supported on JSON map columns          |
| `add`       | `column + value`         | Append one element to JSON array           |
| `remove`    | `column - value`         | Remove matching elements from JSON array   |
| `addAll`    | —                        | Append many elements                       |
| `removeAll` | —                        | Remove all elements matching any in list   |

Columns with **`UpdatedAtTransformer`** are set to `DateTime.now()` automatically on update. **`CreatedAtTransformer`** columns are skipped when applying updates.

Plain `ObjectUpdate` maps on **JSON map columns** use SQLite `json_patch` (RFC 7396 merge patch).

## Custom operations

Override **`custom`** to handle operation names that are not `create`, `update`, `delete`, `view`, or `list`:

```dart
@override
rd.ToQuery<PostCollection, Post> custom(
  String operation, {
  Where? where,
  Map<String, dynamic>? values,
}) {
  return switch (operation) {
    'archive' => db
        .update(posts)
        .setAll([UpdateableColumn(table['archived'], true)])
        .where(RawSqlFilter(where!.sql(table.name)))
        .toQuery(),
    _ => super.custom(operation, where: where, values: values),
  };
}
```

The default implementation throws `UnimplementedError`. Custom operations must be allowed in your **rules** for the collection (same as any other operation name).

## Internal tables

Framework-managed SQLite tables (`_jwt`, `_log`, `_rate_limit`, `_auth_challenges`, `_raindrop_migrations`) ship with built-in operations. They are **always** merged into the `db_operations` executable; you do not add files for them under `operationsPath`.

## Compilation and analysis

When operations are compiled:

1. **`dart analyze`** runs on `operationsPath`. Compilation aborts if analysis fails.
2. **`OperationGenerator`** writes `.dart_tool/zonai/db_operations.dart`, importing every operations file plus internal operations, and wiring `DbOperations(...).start()`.
3. **`dart compile exe`** produces `.zonai/executables/db_operations.exe` (path configurable via the Zonai data directory).

If the executable is missing at runtime, the server logs instructions to add files under `operationsPath` and run `zonai serve` or press **`c`** to recompile.

## Commands

From your app directory (where `zonai.yaml` lives):

```bash
# Compile all workers, including operations
dart run zonai compile

# Dev server: watches operationsPath and recompiles on change
dart run zonai serve
```

While `serve` is running, press **`c`** to recompile all workers (config, rules, extensions, operations, rate limits).

See also **[config-and-env-flavors.md](config-and-env-flavors.md)** for `--flavor` and env defines passed into worker executables.

## Configuration

`zonai.yaml`:

```yaml
operationsPath: lib/src/operations
```

## Minimal example

From `apps/playground/lib/src/operations/item_operations.dart`:

```dart
import 'package:zonai_playground/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class ItemOperations extends CollectionOperations<ItemCollection, Item> {
  ItemOperations() : super(items);
}

ItemOperations main() => ItemOperations();
```

No overrides are required for standard CRUD; rules and the default `CollectionOperations` implementation handle SQL for typical REST endpoints.

## See also

- **[rules.md](rules.md)** — collection and record access rules (checked before SQL runs)
- **[extensions.md](extensions.md)** — lifecycle hooks around mutations and auth (before/after SQL)
- **[rate-limiting.md](rate-limiting.md)** — per-operation request limits (separate worker, same compile flow)
- **[config-and-env-flavors.md](config-and-env-flavors.md)** — worker executables and compile-time env
- **`libs/zonai_schema/lib/src/operations/collection_operations.dart`** — full implementation of query helpers and auth mixins
