---
title: Operations Overview
description: What operations do and when you need to write them.
---

Operations are the layer that turns a request into SQL. For every table declared under `schemasPath`, Zonai generates default operations (create, update, delete, view, list, count, **and live stream**) at compile time, so most tables need no operations code at all. An operations file is where you override those defaults, add custom JWT claims, or add a named, non-CRUD operation.

<Info>

**Built-in live queries:** `GET /db/stream`, `/db/stream/list`, `/db/stream/count` — use `client.db.listen` in Dart. Guide: [Streaming (Live Queries)](/operations/streaming).

</Info>

## Where operations sit in a request

1. The request passes rate limiting and then [rules](/rules/overview). A rules denial is a `403`, and no SQL is built.
2. The server asks the table's `TableOperations` — your file from `operationsPath`, or the generated default — for the query.
3. The query is translated to SQLite SQL and executed by the server. Operations never run queries themselves; they only build them.

## Do you need an operations file?

| Situation | Operations file? |
| --- | --- |
| Standard CRUD on a regular table | No — [default operations](/operations/default-operations) cover it |
| Auth table with default sign-in, JWT and email-link behaviour | No |
| Extra JWT claims, a per-table JWT lifetime, or auth email link paths | Yes — [Auth Operations](/operations/auth-operations) |
| A named state transition (`archive`, `reserve`) | Yes — [custom operations](#custom-operations) |
| A column whose value the server must set, never the client | Yes — [override `insert`](#filling-in-a-server-generated-value) |
| A read-only join or projection | Yes — a [view](/operations/views) |

## Creating an operations file

Add a `.dart` file under `operationsPath` (default `lib/src/operations`). It exports a `main()` that returns the `TableOperations` for one table; pass the schema getter to the superclass:

```dart
import 'package:my_app/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class PostOperations extends TableOperations<PostTable, Post> {
  PostOperations() : super(posts);

  // Override the operations you want to customize here.
}

PostOperations main() => PostOperations();
```

- Every `.dart` file under `operationsPath` is discovered automatically. A missing or empty directory is fine: every table still gets its defaults.
- A file replaces the default for **its table only**. Every other table keeps its generated default.
- **At most one file per table.** Two files returning operations for the same table name fail at startup with `Operations already registered for <table>`.
- For an auth table, also mix in `AuthOperations` — see [Auth Operations](/operations/auth-operations).
- Framework tables (`_jwt`, `_log`, `_photos`, …) ship their own operations. You never add files for them.

## Built-in query helpers

`TableOperations` builds each standard operation with one overridable method. Override a method only when you need different SQL.

| Method | Builds | Serves |
| --- | --- | --- |
| `insert` | Insert one row from a map, `RETURNING` the row | `POST /db` |
| `insertMany` | Insert typed rows | `POST /db/many` |
| `update` | Update rows matching a `Where` | `PATCH /db`, `PATCH /db/many` |
| `delete` | Delete rows matching a `Where` | `DELETE /db`, `DELETE /db/many` |
| `list` | Select with filter, limit, offset, `order_by`, `group_by` | `GET /db` (limit 1), `GET /db/list`, streams |
| `count` | Count matching rows | `GET /db/count`, `/db/stream/count` |
| `custom` | Anything else, by operation name | `PATCH /db/custom/:operation` |

The helpers return Raindrop builders, so an override can call `super` and chain more clauses onto the result.

## Custom Operations

Override `custom` to handle an operation name that isn't one of the standard ones. It is reached via `PATCH /db/custom/:operation` (or `PATCH /db/custom/:operation/many`) — the operation name travels on the URL, and `table` / `where` / `updates` go in the body like every other `/db` route:

```dart
import 'package:my_app/src/schemas/posts.dart';
// `.returning()` on an update is not re-exported by zonai_schema, so import it
// directly. `show` keeps the import to the one extension you need.
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/builders/returning.dart'
    show SQLiteUpdateReturning;
import 'package:zonai_schema/zonai_schema.dart';

final class PostOperations extends TableOperations<PostTable, Post> {
  PostOperations() : super(posts);

  @override
  ToQuery<Schema<Post>, Post> custom(
    String operation, {
    Where? where,
    List<Update> updates = const [],
  }) {
    return switch (operation) {
      'archive' when where != null =>
        update(updates, where: where).returning(),
      _ => super.custom(operation, where: where, updates: updates),
    };
  }
}

PostOperations main() => PostOperations();
```

A custom operation that writes must end in `.returning()`: `update(...)` alone builds a query that returns nothing, which is not the `ToQuery<Schema<R>, R>` that `custom` has to return.

`updates` uses the same `Update` vocabulary as the standard `update` (see [Update value types](/operations/default-operations#update-value-types)), which is what lets `archive` delegate straight to it.

Every custom operation also needs an entry in **both** rules classes, or it is denied — see [Table Rules: Custom Operations](/rules/table-rules#custom-operations) and [Row Rules: Custom Operations](/rules/row-rules#custom-operations).

What the server answers when a custom operation is misused:

| Request | Result |
| --- | --- |
| Operation name not handled by your `custom` (the default throws) | `400`, "Custom operation … is not implemented" |
| Operation name not a key in the rules' `customOperations` | `403`, and a warning is logged naming the operation |
| `updates` sent with no `where` | `400` — a table-wide write would otherwise be authorized by the table rule alone |
| Operation named `create`, `update`, `delete`, `view`, `list` or `count` | Refused — a custom operation cannot reuse a standard name. Rename it |

### Declaring server-side writes

A row rule for a custom operation gets `before` and `after`, and `after` is computed by replaying the request's `updates` over `before`. `custom` returns a whole query, so Zonai cannot see inside it. When the operation writes something of its own — a server-computed column, a `use_count = use_count + 1` — that write is invisible to the rule. `after` comes back as a copy of `before`, and a rule that compares them refuses **every** call, with both the rule and the SQL looking correct.

Override `customUpdates` to tell the rules what `custom` is going to write. Build both from the same list so they cannot drift apart:

```dart no-analyze
// The one list both halves read.
static final _redeem = [Update.column('use_count', const Increment())];

@override
ToQuery<Schema<Invite>, Invite> custom(String operation, {Where? where, List<Update> updates = const []}) =>
    switch (operation) {
      'redeem' => update(_redeem, where: where!).returning(),
      _ => super.custom(operation, where: where, updates: updates),
    };

@override
List<Update> customUpdates(String operation, {Where? where, List<Update> updates = const []}) =>
    switch (operation) {
      'redeem' => _redeem,
      _ => super.customUpdates(operation, where: where, updates: updates),
    };
```

`no-analyze`: `InviteTable` is an illustrative table the docs' fixtures do not define.

The declared updates are **simulated, never executed** — `custom` remains the only thing that writes. The default returns the caller's `updates` unchanged, so an operation like `archive` above needs nothing. When a custom operation's row rule runs with no updates from either side, Zonai logs a warning once per table/operation pair naming `customUpdates`.

## Filling in a server-generated value

Override `insert` when a column's value must never come from the client — a generated API key, a computed checksum:

```dart no-analyze
final class ClientAppOperations extends TableOperations<ClientAppTable, ClientApp> {
  ClientAppOperations() : super(clientApps);

  @override
  insert(Map<String, dynamic> data) {
    return super.insert({...data, 'api_key': _generateApiKey()});
  }
}
```

`no-analyze`: `ClientAppTable` is an illustrative table the docs' fixtures do not define.

Declare that column with `$.serverGenerated(...)`, not `$.text(...)`. Rules run **before** operations, against a row built from the raw request — so with a plain non-nullable `$.text` column the client never sends, building that row fails before your `insert` override ever runs. A `serverGenerated` column is a non-nullable `TEXT` column that is filled with a blank placeholder when the payload omits it. Unlike `$.password`, its value is returned in responses, and the dashboard shows it read-only. See [Defining Tables](/schemas/defining-tables#server-generated-columns).

## Compiling and reloading

Operations compile into the server binary and into the `db_operations` worker. Compiling runs `dart analyze` on `operationsPath` first, and **an analysis error aborts the compile**.

In dev, `zonai serve` watches `operationsPath` and recompiles on change; press `c` to force a recompile. If your project depends on `package:zonai` (so operations run in-process), restart `serve` after editing them so the linked code reloads. Schema changes are picked up on the next compile (`zonai compile`, `c` in `serve`, or `zonai build`).

- [Default Operations](/operations/default-operations) — request and response shapes for every built-in route
- [Streaming (Live Queries)](/operations/streaming) — `/db/stream*` and `client.db.listen`
- [Auth Operations](/operations/auth-operations) — JWT claims and auth email link settings
- [Views](/operations/views) — read-only, query-defined collections
