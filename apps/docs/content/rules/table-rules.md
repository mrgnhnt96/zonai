---
title: Table Rules
description: Controlling which operations are allowed on a table based on the JWT.
---

Table rules control whether a JWT is permitted to perform an operation on a table. They run before any SQL, and they do not see individual rows.

## Creating Table Rules

Create `<table>_table_rules.dart` in `rulesPath` and extend `TableRules`:

```dart
import 'package:my_app/src/schemas/tasks.dart';
import 'package:zonai_schema/zonai_schema.dart';

TaskTableRules main() => TaskTableRules();

final class TaskTableRules extends TableRules<TaskTable, Task> {
  TaskTableRules() : super(tasks);

  @override
  Future<bool> canCreate(Jwt? jwt) async => jwt != null;
  @override
  Future<bool> canList(Jwt? jwt) async => true;
  @override
  Future<bool> canView(Jwt? jwt) async => true;
  @override
  Future<bool> canUpdate(Jwt? jwt) async => jwt != null;
  @override
  Future<bool> canDelete(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;
}
```

A table also needs a [row rules](/rules/row-rules) file — without one, every row-level check is denied.

## Available Methods

| Method | Checked before | Default |
| --- | --- | --- |
| `canCreate(jwt)` | `POST /db`, `POST /db/many` | Admin with `canEdit` |
| `canUpdate(jwt)` | `PATCH /db`, `PATCH /db/many` | Admin with `canEdit` |
| `canDelete(jwt)` | `DELETE /db`, `DELETE /db/many` | Admin with `canEdit` |
| `canView(jwt)` | `GET /db`, `GET /db/stream` | Any admin |
| `canList(jwt)` | `GET /db/list`, `GET /db/count`, `GET /db/stream/list`, `GET /db/stream/count` | Any admin |

Every non-admin caller — including an unauthenticated one — is denied by an unoverridden method. `count` has no method of its own: it is gated by `canList`.

Streaming (`/db/stream*`) reuses the same checks as ordinary reads — there is no separate `canStream*` method. See [Streaming](/operations/streaming).

After the table rule passes, [row rules](/rules/row-rules) run for the rows involved.

## Common Patterns

Public read, authenticated write:

```dart in:table-rules
@override Future<bool> canList(Jwt? jwt) async => true;
@override Future<bool> canView(Jwt? jwt) async => true;
@override Future<bool> canCreate(Jwt? jwt) async => jwt != null;
@override Future<bool> canUpdate(Jwt? jwt) async => jwt != null;
@override Future<bool> canDelete(Jwt? jwt) async => jwt != null;
```

Admin-only deletes, on top of the same reads:

```dart in:table-rules
@override Future<bool> canDelete(Jwt? jwt) async =>
    jwt?.admin.isAdmin ?? false;
```

Fully public reads — still needs the rules file, since a table with no rules is closed to everyone:

```dart in:table-rules
@override Future<bool> canList(Jwt? jwt) async => true;
@override Future<bool> canView(Jwt? jwt) async => true;
```

## Accessing Custom JWT Claims

Custom claims added via [Auth Operations](/operations/auth-operations) are available via `jwt?.claims`:

```dart in:table-rules
@override
Future<bool> canCreate(Jwt? jwt) async {
  return jwt?.claims['plan'] == 'pro';
}
```

See [JWT Claims](/rules/jwt-claims) for all available fields.

## Custom Operations

Named operations that aren't create/update/delete/view/list/count — [`TableOperations.custom`](/operations/overview#custom-operations) — go through `customOperations`, not the methods above. An operation name that isn't a key in the map is denied (`403`, with a warning in the log naming it):

```dart in:table-rules
@override
Map<String, CustomTableOperationRule> get customOperations => {
  'archive': (jwt) async => jwt?.admin.canEdit ?? false,
};
```

Model state transitions (`reserve`, `fill`, `collect`) as their own operations rather than a generic update, so each rule's intent is readable from the operation name.

- Row rules need a matching entry too — see [Row Rules: Custom Operations](/rules/row-rules#custom-operations).
- A key named after a standard operation (`update`, `list`, …) is refused: the standard method would decide the call and your entry would never be consulted. Pick a different name.
- A custom operation called with no `where` has no target row, so only this table-level check runs. Because of that, a request that sends `updates` without a `where` is rejected with `400` — otherwise this (usually permissive) table rule alone would authorize a write to every row.
