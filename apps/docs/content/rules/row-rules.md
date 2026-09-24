---
title: Row Rules
description: Per-row authorization that runs after the row is fetched.
---

Row rules make per-record decisions. They run after the table rule passes and receive the JWT plus a typed row — the stored row for `view`, `list`, `update` and `delete`, or the payload for `create`.

If `canView` returns `false` for any row in the result set, the entire request returns `403 Forbidden` — no data is returned. The same applies to `canUpdate` and `canDelete`: if any matched row fails the check, the mutation is aborted and `403` is returned.

Every table needs a row rules file: with table rules but no row rules, every row-level check is denied.

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
    return jwt?.userId == before.createdBy;
  }

  @override
  Future<bool> canDelete(Jwt? jwt, Task row) async {
    if (jwt?.admin.isAdmin ?? false) return true;
    return jwt?.userId == row.createdBy;
  }
}
```

## Available Methods

| Method | When it runs | Default |
| --- | --- | --- |
| `canView(Jwt? jwt, T row)` | Before returning a row from `view`, `list` or a stream | Any admin |
| `canUpdate(Jwt? jwt, T before, T after)` | Before an `update`, once per matched row | Admin with `canEdit` |
| `canDelete(Jwt? jwt, T row)` | Before a `delete`, once per matched row | Admin with `canEdit` |
| `canCreate(Jwt? jwt, T row)` | Before a `create`; `row` is the payload, not yet in the database | Any admin |

`row`/`before` is the current state of the row from the database (or, for `canCreate`, the data being inserted, built with `Table.safeCreate`). `after` is the row the pending update would produce, computed ahead of the write — exact for every update type, including JSON list/map column operations (`add`/`remove`/`add_all`/`remove_all`, nested map sets, merge patches).

<Info>

**Check ownership against `before`, never `after`.** `after` is built from what the caller asked for, so an ownership test against it lets anyone claim a row by asserting they own it. Compare `after` with `before` only to gate the *transition*.

</Info>

<Info>

Two kinds of column can't reflect the true post-write value in `after`, so don't gate a rule on them:

- **Server-managed columns** (`createdAt`/`updatedAt`/`updatedWhen`) report their pre-write value — the real value is wall-clock write time, which isn't known until the write actually happens.
- **Secret columns** (e.g. a `password` column) are always redacted to `'__REDACTED__'` — the real submitted value is never put in `after`, so it can't leak into rule code.

</Info>

### Gating the transition

Because `canUpdate` sees both sides of the write, a rule can refuse a specific change rather than the whole update — for example, only an admin may reassign a row's owner:

```dart in:row-rules
@override
Future<bool> canUpdate(Jwt? jwt, Task before, Task after) async {
  if (after.ownerId != before.ownerId) {
    return jwt?.admin.isAdmin ?? false; // only an admin may reassign an owner
  }
  return jwt?.userId == before.ownerId;
}
```

Upgrading from a release where `canUpdate` took a single `row`: rename it to `before` and add the `after` parameter. Behaviour is unchanged if you ignore `after`.

## Row Rules vs. Table Rules

Table rules run first. If the table rule denies, row rules never run and the request returns `403` before any SQL executes.

Row rules run once the rows involved have been read (for `create`, on the payload before the insert) — see [Request Pipeline](/core-concepts/request-pipeline). Semantics are per-row for `list` and `view` — if any row fails `canView`, the whole request fails. Evaluation is **batched** (one rules call for the page), and tables that override `requiresPerRowCheck => false` skip row-rule work after table access succeeds.

For large result sets, keep row rules fast — avoid database queries inside them when possible.

### Skipping per-row checks

```dart in:row-rules
@override
bool get requiresPerRowCheck => false; // public table: table rules are enough
```

Default is `true`. Use `false` only when every row that passes table rules is always visible/mutable for that caller class.

## Custom Operations

Named operations that aren't create/update/delete/view/list/count — [`TableOperations.custom`](/operations/overview#custom-operations) — go through `customOperations`, keyed by the same operation name. An operation name that isn't a key in the map is denied, same as any unoverridden method above:

```dart in:row-rules
@override
Map<String, CustomRowOperationRule<Task>> get customOperations => {
  'archive': (jwt, before, after) async =>
      jwt?.admin.canEdit ?? false,
};
```

`before`/`after` work exactly like `canUpdate`'s — `after` is simulated from the operation's `updates` ahead of the write, so a rule can gate on the transition itself (e.g. only an admin may set `status` to `'archived'`). Table rules need a matching entry too — see [Table Rules: Custom Operations](/rules/table-rules#custom-operations).

Those `updates` are the ones on the request. If your `custom()` writes something the caller never sent — a server-computed column, a self-referencing `count = count + 1` — Zonai cannot see it, because `custom()` returns a whole query rather than a list of updates. `after` then arrives as a copy of `before`, and a rule comparing the two refuses every call while both the rule and the SQL look correct. Declare those writes by overriding [`customUpdates`](/operations/overview#declaring-server-side-writes) on the same `TableOperations`; Zonai warns once per table/operation pair when a custom operation's row rule runs with nothing to simulate.
