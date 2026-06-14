# Table operations

Zonai turns HTTP and auth requests into SQL through **collection operations**: Dart classes that describe how each table is read and written. For every collection declared under **`schemasPath`** (default `lib/src/schemas`), Zonai generates **default operations** at compile time — you do not need an operations file unless you want to customize behavior.

Optional overrides live under **`operationsPath`** (default `lib/src/operations`, overridable in `zonai.yaml`). At compile time, Zonai bundles any custom operations files with built-in internal-table operations into the `db_operations` worker executable.

Operations do **not** run queries themselves. The server sends a structured request to the worker; the worker returns SQL and bound values; the server executes that SQL against SQLite after rules and rate limits have been checked.

## How it works

1. An HTTP or auth handler needs SQL for a collection (for example `create` on `items`).
2. The server sends an **operation request** to the compiled `db_operations` worker.
3. The worker finds the matching `TableOperations` instance (keyed by table name) — either a custom file from `operationsPath` or a generated default — and builds a Raindrop query.
4. The worker translates the query to SQL for the configured dialect (SQLite by default) and returns it.
5. The server runs the SQL on the database and returns the result to the client.

While `serve` is running, changes under `operationsPath` trigger a recompile so custom SQL generation stays in sync with your Dart code without restarting the database. Schema changes under `schemasPath` are picked up the next time workers are compiled (`dart run zonai compile` or **`c`** in `serve`).

## When you need an operations file

| Situation | Operations file required? |
| --------- | ------------------------- |
| Standard CRUD on a regular collection | No — default operations are generated from the schema |
| Auth collection with default sign-in / JWT / email-link behavior | No |
| Custom CRUD SQL, `custom()` operations, JWT claims, or auth email settings | Yes |

## Default operations

At compile time, **`OperationGenerator`** scans **`schemasPath`** for `table(...)` and `authTable(...)` declarations and passes those schema getters to the worker as `tables: [...]`. For each table without a matching operations file, the worker uses:

- **`DefaultTableOperations`** — standard CRUD for regular collections
- **`DefaultAuthTableOperations`** — same CRUD plus default **`AuthOperations`** (JWT claims, magic-link / reset-password / verify-email config) for auth collections

These classes extend **`TableOperations`** and reuse the same [built-in query helpers](#built-in-query-helpers). Custom operations files replace the default for that table only.

## Project layout

Schemas (required for default operations):

```text
lib/src/schemas/
  items.dart
  users.dart
  posts.dart
```

Operations (optional — add only when customizing):

```text
lib/src/operations/
  user_operations.dart   # example: custom JWT claims on users
```

Each operations `.dart` file must export a **`main()`** that returns a **`TableOperations`** instance for one collection:

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserOperations extends TableOperations<UserTable, User>
    with AuthOperations {
  UserOperations() : super(users);

  @override
  Future<Claims> addClaims({required Jwt jwt}) async {
    return Claims({'is_awesome': true});
  }
}

UserOperations main() => UserOperations();
```

Only files with a `.dart` extension under `operationsPath` are included. If the directory is missing or empty, the worker still compiles: default operations are generated for every collection in `schemasPath`, plus **built-in internal table operations** (see [Internal tables](#internal-tables)).

Define **at most one operations file per collection**. Each file’s `main()` must return a non-null `TableOperations`. A custom file overrides the generated default for that table name. If two files target the same table name, registration fails at startup.

## Base classes

| Table type    | Extend / mix in                                 | Example                         |
| ------------------ | ----------------------------------------------- | ------------------------------- |
| Regular collection | `TableOperations<S, R>`                    | Items, posts, companies         |
| Auth collection    | `TableOperations<S, R>` + `AuthOperations` | Users with sign-in / JWT claims |

`TableOperations` is parameterized by your **schema** (`S`) and **row type** (`R`). Pass the schema getter (for example `items`, `users`) to the superclass constructor.

### Auth collections

Auth collections mix in **`AuthOperations`** to customize JWT claims and auth email link settings:

```dart
final class UserOperations extends TableOperations<UserTable, User>
    with AuthOperations {
  UserOperations() : super(users);

  @override
  Future<Claims> addClaims({required Jwt jwt}) async {
    return Claims({'is_awesome': true});
  }
}

UserOperations main() => UserOperations();
```

| Method / property     | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `addClaims`           | Extra JWT claims merged into tokens for this collection                 |
| `jwtExpiresIn`        | Optional JWT lifetime override (`null` uses `AppConfig.jwtExpiresIn`)   |
| `magicLinkConfig`     | Magic-link path and expiry (default `/auth/magic-link`, 10 minutes)     |
| `resetPasswordConfig` | Reset-password path and expiry (default `/auth/reset-password`, 10 min) |
| `verifyEmailConfig`   | Verify-email path and expiry (default `/auth/verify-email`, 24 hours)   |

Access token lifetime defaults to **14 days** via `AppConfig.jwtExpiresIn`. Set `jwtExpiresIn` on the config worker to change the global default; override per collection with the `jwtExpiresIn` getter on `AuthOperations`.

Auth emails use magic-link / reset / verify paths with `AppConfig.baseUrl` to build link URLs. See **[email.md](email.md)** for templates and SMTP configuration.

The framework also uses operations for auth-specific SQL (lookup by email, sign-up row shape, column name resolution for password/email/id fields). You normally only override the methods above unless you need custom query behavior via the standard CRUD helpers.

## Built-in query helpers

`TableOperations` exposes Raindrop builders for the operations the API uses. Override a method when you need different SQL; otherwise the defaults apply.

| Method       | Used for                                              |
| ------------ | ----------------------------------------------------- |
| `insert`     | Create one row from a map                             |
| `insertMany` | Bulk insert typed rows                                |
| `update`     | Patch rows matching a `Where` clause                  |
| `delete`     | Delete rows matching a `Where` clause                 |
| `list`       | Select with optional filter, limit, offset, `order_by`, `groupBy` |
| `count`      | Count rows with optional filter                       |
| `custom`     | Non-standard operation names (override required)      |

Builders are awaitable or can be chained further before awaiting. Inserts use `.returning()` so the server can read created rows.

### Standard operations and HTTP

These map to `TableOperation` names in rules and rate limiting:

| Operation | Operations helper | Typical HTTP use                |
| --------- | ----------------- | ------------------------------- |
| `create`  | `insert`          | `POST /db`, `POST /db/many`       |
| `update`  | `update`          | `PATCH /db`, `PATCH /db/many`   |
| `delete`  | `delete`          | `DELETE /db`, `DELETE /db/many` |
| `view`    | `list` (limit 1)  | `GET /db`, stream-one           |
| `list`    | `list`            | `GET /db/list`, stream-list     |
| `count`   | `count`           | `GET /db/count`                 |

`list` requests accept an optional `order_by` array of `{ "column": "...", "direction": "asc" | "desc" }` terms. Columns must exist on the collection schema; unknown columns are rejected when SQL is built.

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

### Password columns

Password columns on auth collections receive special treatment during updates.

**Automatic hashing.** When an update targets the password column — whether via `Update.column` or inside an `Update.object` map — Zonai automatically hashes the plain-text value with Argon2id before writing it to SQLite. The stored value is always `<saltBase64>.<digestBase64>`; the plain-text password never touches the database.

**Admin-only.** Updating a password column requires an admin JWT with `canEdit: true`. Any attempt by a non-admin (or an unauthenticated request) throws `PasswordUpdateForbiddenException` → **403**.

**Literal values only.** The password update value must be a plain string literal (`UpdateValue.literal`). Arithmetic or list operations (`increment`, `decrement`, `add`, `remove`, etc.) on a password column throw `InvalidPasswordUpdateException` → **422**.

Example — updating a user's password as an admin:

```dart
await zonaiDB.update(
  'users',
  UpdatePayload(
    jwt: adminJwt,                        // must be admin with canEdit
    where: Eq('id', userId),
    updates: [
      ColumnUpdate('password', Literal('new-plain-text-password')),
    ],
  ),
);
```

The value `'new-plain-text-password'` is hashed before the SQL `UPDATE` runs. After the call, sign-in with the new password succeeds and the old password is rejected.

| Condition | Exception | HTTP status |
| --------- | --------- | ----------- |
| Caller is not an admin or `canEdit` is false | `PasswordUpdateForbiddenException` | 403 |
| Update value is not a plain string literal | `InvalidPasswordUpdateException` | 422 |

## Custom operations

Override **`custom`** to handle operation names that are not `create`, `update`, `delete`, `view`, or `list`:

```dart
@override
rd.ToQuery<PostTable, Post> custom(
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

1. **`dart analyze`** runs on `operationsPath` when that directory exists and contains `.dart` files. Compilation aborts if analysis fails.
2. **`OperationGenerator`** writes `.dart_tool/zonai/db_operations.dart`, importing custom operations files (if any), internal operations, and schema getters from `schemasPath`, and wiring `DbOperations(operations: [...], tables: [...]).start()`.
3. **`dart compile exe`** produces `.zonai/executables/db_operations.exe` (path configurable via the Zonai data directory).

If the executable is missing at runtime, the server logs instructions to run `zonai serve` or press **`c`** to recompile.

## Commands

From your app directory (where `zonai.yaml` lives):

```bash
# Compile all workers, including operations
dart run zonai compile

# Dev server: watches operationsPath and recompiles on change
dart run zonai serve
```

While `serve` is running, press **`c`** to recompile all workers (config, rules, extensions, operations, rate limits, crons).

See also **[config-and-env-flavors.md](config-and-env-flavors.md)** for `--flavor` and env defines passed into worker executables.

## Configuration

`zonai.yaml`:

```yaml
schemasPath: lib/src/schemas
operationsPath: lib/src/operations   # optional overrides
```

## Minimal example

Most collections need **no operations file**. Define the schema under `schemasPath` and the default operations handle standard CRUD for typical REST endpoints (subject to your [rules](rules.md)).

Add a file under `operationsPath` only when you need to customize behavior — for example, extra JWT claims on `users` in `apps/playground/lib/src/operations/user_operations.dart`:

```dart
import 'package:zonai_playground/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserOperations extends TableOperations<UserTable, User>
    with AuthOperations {
  UserOperations() : super(users);

  @override
  Future<Claims> addClaims({required Jwt jwt}) async {
    return Claims({'is_awesome': true});
  }
}

UserOperations main() => UserOperations();
```

## See also

- **[rules.md](rules.md)** — collection and record access rules (checked before SQL runs)
- **[extensions.md](extensions.md)** — lifecycle hooks around mutations and auth (before/after SQL)
- **[rate-limiting.md](rate-limiting.md)** — per-operation request limits (separate worker, same compile flow)
- **[cron.md](cron.md)** — scheduled background jobs (separate worker, same compile flow)
- **[config-and-env-flavors.md](config-and-env-flavors.md)** — worker executables and compile-time env
- **`libs/zonai_schema/lib/src/operations/table_operations.dart`** — full implementation of query helpers and auth mixins
