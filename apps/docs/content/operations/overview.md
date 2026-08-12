---
title: Operations Overview
description: What operations do and when you need to write them.
---

Operations are the layer that translates HTTP requests into SQL statements. For every table, Zonai provides default operations (create, update, delete, view, list, count, **and live stream**) that work with zero code. Operations files are where you override those defaults, add custom JWT claims, or introduce new non-CRUD endpoints.

<Info>

**Built-in live queries:** `GET /db/stream`, `/db/stream/list`, `/db/stream/count` — use `client.db.listen` in Dart. Guide: [Streaming (Live Queries)](/operations/streaming).

</Info>

## When You Don't Need an Operations File

Most tables don't need one. If your table uses standard CRUD with no custom logic, the generated defaults handle everything.

## When You Do Need an Operations File

- Adding custom JWT claims to an auth table's token (e.g. include `role` or `plan` in the JWT)
- Configuring auth flows: password-reset link URL, OTP expiry, magic link redirect
- Adding a named, non-CRUD operation (a state transition like `archive` or `reserve`) via `custom()`

## Custom / Non-CRUD Operations

Override `custom` to handle an operation name that isn't create/update/delete/view/list/count. It's reached via `PATCH /db/custom/:operation` (or `PATCH /db/custom/:operation/many`) — the operation name travels on the URL, `table`/`where`/`updates` in the body like every other `/db` route:

```dart
@override
rd.ToQuery<PostTable, Post> custom(
  String operation, {
  Where? where,
  List<Update> updates = const [],
}) {
  return switch (operation) {
    'archive' => update(updates, where: where!),
    _ => super.custom(operation, where: where, updates: updates),
  };
}
```

`updates` uses the same typed `Update` vocabulary as the standard `update()` builder, which is what lets `archive` above just delegate straight to it. The default implementation throws `UnimplementedError`. A custom operation must also be allowed in your rules for the collection — see [Table Rules: Custom Operations](/rules/table-rules#custom-operations) and [Row Rules: Custom Operations](/rules/row-rules#custom-operations).

## Creating an Operations File

Create a `.dart` file in `operationsPath` for the table you want to customize. Export a `main()` function that returns a `TableOperations` instance:

```dart
import 'package:my_app/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class PostOperations extends TableOperations<PostTable, Post> {
  PostOperations() : super(posts);

  // Override the operations you want to customize here.
}

PostOperations main() => PostOperations();
```

All operations files in `operationsPath` are auto-discovered. Define at most one file per table.

## The Operations Runtime

Operations compile into the project-linked binary (in-process on the default path) and into `db_operations.exe` for force-workers / ping. In dev mode, `zonai serve` regenerates entry files and recompiles workers on change — restart serve after editing ops so linked code reloads. Press `c` to force a recompile manually.

- [Streaming (Live Queries)](/operations/streaming) — `/db/stream*` and `client.db.listen`, for live UI
- [Default Operations](/operations/default-operations) — the built-in CRUD + stream routes for every table
- [Auth Operations](/operations/auth-operations) — JWT claims and auth flow configuration
