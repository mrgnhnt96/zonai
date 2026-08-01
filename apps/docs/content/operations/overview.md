---
title: Operations Overview
description: What operations do and when you need to write them.
---

Operations are the layer that translates HTTP requests into SQL statements. For every table, Zonai provides default operations (create, update, delete, view, list, count) that work with zero code. Operations files are where you override those defaults, add custom JWT claims, or introduce new non-CRUD endpoints.

## When You Don't Need an Operations File

Most tables don't need one. If your table uses standard CRUD with no custom logic, the generated defaults handle everything.

## When You Do Need an Operations File

- Adding custom JWT claims to an auth table's token (e.g. include `role` or `plan` in the JWT)
- Configuring auth flows: password-reset link URL, OTP expiry, magic link redirect

## Creating an Operations File

Create a `.dart` file in `operationsPath` for the table you want to customize. Export a `main()` function that returns a `TableOperations` instance:

```dart
import 'package:my_app/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class PostOperations extends TableOperations<PostTable, Post> {
  PostOperations() : super(posts);

  @override
  // Override methods here
}

PostOperations main() => PostOperations();
```

All operations files in `operationsPath` are auto-discovered. Define at most one file per table.

## The Operations Runtime

Operations compile into the project-linked binary (in-process on the default path) and into `db_operations.exe` for force-workers / ping. In dev mode, `zonai serve` regenerates entry files and recompiles workers on change — restart serve after editing ops so linked code reloads. Press `c` to force a recompile manually.

- [Default Operations](/operations/default-operations) — the built-in CRUD for every table
- [Auth Operations](/operations/auth-operations) — JWT claims and auth flow configuration
