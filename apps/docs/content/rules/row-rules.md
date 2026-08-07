---
title: Row Rules
description: Per-row authorization that runs after the row is fetched.
---

Row rules run after the database returns results. They receive the JWT and the actual row data, enabling per-record authorization decisions.

If `canView` returns `false` for any row in the result set, the entire request returns `403 Forbidden` — no data is returned. The same applies to `canUpdate` and `canDelete`: if the fetched row fails the check, the mutation is aborted and `403` is returned.

<Info>
`canView` also applies to each emission from `/db/stream` and `/db/stream/list`. Live queries are not a rules bypass. See [Streaming](/operations/streaming).
</Info>

## Creating Row Rules

Create `<table>_row_rules.dart` in `rulesPath` and extend `RowRules`:

```dart
import 'package:my_app/src/schemas/tasks.dart';
import 'package:zonai_schema/zonai_schema.dart';

TaskRowRules main() => TaskRowRules();

final class TaskRowRules extends RowRules<TaskTable, Task> {
  TaskRowRules() : super(tasks);

  @override
  Future<bool> canView(Jwt? jwt, Task row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Task before, Task after) async {
    // Admins can always edit; owners can edit their own rows
    if (jwt?.admin.isAdmin ?? false) return true;
    return jwt?.userId == before.createdBy.value;
  }

  @override
  Future<bool> canDelete(Jwt? jwt, Task row) async {
    if (jwt?.admin.isAdmin ?? false) return true;
    return jwt?.userId == row.createdBy.value;
  }
}
```

## Available Methods

| Method                                    | When It Runs                                                        |
| ------------------------------------------ | -------------------------------------------------------------------- |
| `canView(Jwt? jwt, T row)`                 | Before returning a row in `view` or `list`                         |
| `canUpdate(Jwt? jwt, T before, T after)`   | Before executing an `update`                                       |
| `canDelete(Jwt? jwt, T row)`               | Before executing a `delete`                                        |
| `canCreate(Jwt? jwt, T row)`               | Before executing a `create` (row contains the data to be inserted) |

`row`/`before` is the current state of the row from the database (or, for `canCreate`, the data being inserted). `after` is the row the pending update would produce, computed ahead of the write — exact for every update type, including JSON list/map column operations (`Add`/`Remove`/`AddAll`/`RemoveAll`, nested map sets, merge patches).

<Info>
**Breaking change:** `canUpdate` used to take a single `row` (the pre-write state). It now takes `before` and `after`, matching `Extension.afterUpdateSuccess(T before, T after, Jwt?)`'s existing shape — moved earlier so a rule can reject the write instead of only observing it.

Migrating is mechanical: add the `after` parameter, and use `before` wherever the old code used `row`. If your rule doesn't need to inspect the prospective post-write state, ignore `after` — behavior is unchanged.

```dart
// Before
Future<bool> canUpdate(Jwt? jwt, Task row) async => jwt?.userId == row.createdBy.value;

// After
Future<bool> canUpdate(Jwt? jwt, Task before, Task after) async => jwt?.userId == before.createdBy.value;
```

This unlocks gating on the transition itself, not just the current row — e.g. denying a write that would add a role the caller isn't allowed to grant:

```dart
@override
Future<bool> canUpdate(Jwt? jwt, Item before, Item after) async {
  if (after.roles.contains('admin') && !before.roles.contains('admin')) {
    return jwt?.admin.isAdmin ?? false; // only an existing admin may grant admin
  }
  return jwt?.admin.canEdit ?? false;
}
```
</Info>

## Row Rules vs. Table Rules

Table rules run first (step 1 of the pipeline). If the table rule denies, row rules never run and the request returns `403` before any SQL executes.

Row rules run after the database query (step 5 of the pipeline). Semantics are per-row for `list` and `view` — if any row fails `canView`, the whole request fails. Evaluation is **batched** (one rules call for the page), and tables that override `requiresPerRowCheck => false` skip row-rule work after table access succeeds.

For large result sets, keep row rules fast — avoid database queries inside them when possible.

### Skipping per-row checks

```dart
@override
bool get requiresPerRowCheck => false; // public table: table rules are enough
```

Default is `true`. Use `false` only when every row that passes table rules is always visible/mutable for that caller class.

## Common Patterns

```dart
// Owner-only update/delete
@override
Future<bool> canUpdate(Jwt? jwt, Task before, Task after) async =>
    jwt?.userId == before.authorId.value;

// Admin bypass with owner fallback
@override
Future<bool> canDelete(Jwt? jwt, Task row) async {
  if (jwt?.admin.isAdmin ?? false) return true;
  return jwt?.userId == row.authorId.value;
}

// Public view always
@override
Future<bool> canView(Jwt? jwt, Task row) async => true;
```
