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
  Future<bool> canCount(Jwt? jwt) async => true;
  @override
  Future<bool> canView(Jwt? jwt) async => true;
  @override
  Future<bool> canUpdate(Jwt? jwt) async => jwt != null;
  @override
  Future<bool> canDelete(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;
}
```

All unoverridden methods default to `false` (deny).

## Available Methods

| Method           | Endpoint Checked Before                                      | Default |
| ---------------- | ------------------------------------------------------------ | ------- |
| `canCreate(jwt)` | `POST /db`                                                   | `false` |
| `canList(jwt)`   | `GET /db/list`, `GET /db/stream/list`                        | `false` |
| `canCount(jwt)`  | `GET /db/count`, `GET /db/stream/count`                      | `false` |
| `canView(jwt)`   | `GET /db`, `GET /db/stream`                                  | `false` |
| `canUpdate(jwt)` | `PATCH /db`                                                  | `false` |
| `canDelete(jwt)` | `DELETE /db`                                                 | `false` |

Streaming (`/db/stream*`) reuses the same `canView` / `canList` / `canCount` checks as ordinary reads — there is no separate `canStream*` method. See [Streaming](/operations/streaming).

For `view`, `update`, and `delete`: the table rule runs first, then row rules run (if the table rule passes).

## Common Patterns

```dart
// Public read, authenticated write
@override Future<bool> canList(Jwt? jwt) async => true;
@override Future<bool> canView(Jwt? jwt) async => true;
@override Future<bool> canCreate(Jwt? jwt) async => jwt != null;
@override Future<bool> canUpdate(Jwt? jwt) async => jwt != null;
@override Future<bool> canDelete(Jwt? jwt) async => jwt != null;

// Admin-only
@override Future<bool> canDelete(Jwt? jwt) async => jwt?.admin.isAdmin ?? false;

// Fully public (no file needed — but explicit is fine too)
@override Future<bool> canList(Jwt? jwt) async => true;
// etc.
```

## Accessing Custom JWT Claims

Custom claims added via [Auth Operations](/operations/auth-operations) are available via `jwt?.claims`:

```dart
@override
Future<bool> canCreate(Jwt? jwt) async {
  return jwt?.claims['plan'] == 'pro';
}
```

See [JWT Claims](/rules/jwt-claims) for all available fields.
