---
title: Rules Overview
description: How Zonai's two-layer authorization model works.
---

Rules are the authorization layer in Zonai. Every request passes through rules before SQL is built. A denial returns `403 Forbidden` immediately — no SQL runs, no extension fires.

**What you need to do:** for every table your API exposes, add two files under `rulesPath` (default `lib/src/rules`) — a table rules file and a row rules file. A table without them is closed to everyone but admins.

<Info>

**Streaming reuses read rules.** `canView` gates `/db/stream`, and `canList` gates `/db/stream/list` and `/db/stream/count`. There is no separate `canStream*`. See [Streaming](/operations/streaming).

</Info>

## Two Layers

**Table rules** decide whether the caller may perform an operation on a table at all. They see only the JWT and the operation — never a row.

**Row rules** decide whether the caller may perform the operation on **this row**. They receive the JWT and a typed row: the payload for `create`, the stored row for `view`/`update`/`delete` (plus the simulated post-write row for `update`).

| Operation | Table check | Row check |
| --- | --- | --- |
| `create` (`POST /db`, `/db/many`) | `canCreate` | `canCreate(jwt, payloadRow)` |
| `update` (`PATCH /db`, `/db/many`) | `canUpdate` | `canUpdate(jwt, before, after)` per row |
| `delete` (`DELETE /db`, `/db/many`) | `canDelete` | `canDelete(jwt, row)` per row |
| `view` (`GET /db`, `/db/stream`) | `canView` | `canView(jwt, row)` |
| `list` (`GET /db/list`, `/db/stream/list`) | `canList` | `canView(jwt, row)` on **each** returned row |
| `count` (`GET /db/count`, `/db/stream/count`) | `canList` | — |
| custom operation | `customOperations[name]` | `customOperations[name]` |

The table check runs first. If it denies, row rules never run.

## Return Value Semantics

Rule methods return `Future<bool>`:

- `true` → allowed, pipeline continues
- `false` → `403 Forbidden`, request stops immediately

This applies to `canView` on a list too: if **any** row fails, the entire request returns `403` — not a partial or filtered response. Design `canList` and row `canView` together, or filter in the query so the database only returns rows the caller may see.

## Default Deny

Rules fail closed at every level:

- **No rules file for a table** → every operation is denied, for everyone including admins. A table with table rules but no row rules is denied at the row level.
- **A method you don't override** → only an admin token passes: `canEdit` admins for writes, any admin for reads. See [Table Rules](/rules/table-rules#available-methods) and [Row Rules](/rules/row-rules#available-methods) for the exact defaults.
- **A custom operation name missing from `customOperations`** → denied.

Unauthenticated callers (`jwt == null`) are denied unless you override a method to allow them.

## Files and Registration

Each file under `rulesPath` exports a `main()` that returns one rules instance:

```text
lib/src/rules/
  task_table_rules.dart   # TaskTableRules extends TableRules<TaskTable, Task>
  task_row_rules.dart     # TaskRowRules extends RowRules<TaskTable, Task>
```

| Table type | Table rules | Row rules |
| --- | --- | --- |
| Regular table | [`TableRules<S, R>`](/rules/table-rules) | [`RowRules<S, R>`](/rules/row-rules) |
| Auth table | [`AuthTableRules<S, R>`](/rules/auth-rules) | [`AuthRowRules<S, R>`](/rules/auth-rules) |
| View | [`ViewTableRules<S, R>`](/operations/views#writing-the-rules) | [`ViewRowRules<S, R>`](/operations/views#writing-the-rules) |

- **One table rules file and one row rules file per table.** Registering a second of the same kind for a table fails when the rules load (`Table rules already registered for <table>`).
- Framework tables (`_jwt`, `_log`, `_rate_limit`, …) ship built-in rules that deny non-admin access and cannot be overridden. The one exception is [`_photos`](/rules/photo-rules).

## Compiling and Reloading

Rules compile into the `db_rules` worker (and run in-process only when your project depends on `package:zonai`; see [Workers](/core-concepts/workers)). Compiling runs `dart analyze` on `rulesPath` first, and **an analysis error aborts the compile**. In dev, `zonai serve` recompiles on change and `c` forces a recompile.

## The JWT Parameter

Every rule method receives a `Jwt?` — nullable because the request may be unauthenticated:

```dart in:table-rules
// Public endpoint — allow everyone
@override
Future<bool> canList(Jwt? jwt) async => true;

// Authenticated endpoint — require sign-in
@override
Future<bool> canCreate(Jwt? jwt) async => jwt != null;

// Admin-only
@override
Future<bool> canDelete(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;
```

See [JWT Claims](/rules/jwt-claims) for all available fields.

## Related

- [Table Rules](/rules/table-rules) — operation-level access control
- [Row Rules](/rules/row-rules) — per-row access control
- [Auth Rules](/rules/auth-rules) — sign-up/sign-in/password-reset control
- [Photo Rules](/rules/photo-rules) — the one framework table you can re-rule
- [JWT Claims](/rules/jwt-claims) — what's in the token
