---
title: Quick Start
description: Build and run your first Zonai project from scratch in under 10 minutes.
---

This guide walks through creating a small REST API with a `users` auth table and a `tasks` table. By the end you will have a running server and be able to sign up, sign in, and create tasks.

## Step 1: Create a Dart Project

```bash
dart create my_app && cd my_app
```

Add `zonai_schema` — the package your tables, rules and operations are written
against — to `pubspec.yaml`:

```yaml
dependencies:
  zonai_schema: ^0.1.0
```

Run `dart pub get`.

The `zonai` CLI is not a pub package. It is a pre-compiled binary that lives in
your project root; if you have not already downloaded it, see
[Installation](/getting-started/installation).

## Step 2: Initialize Zonai

```bash
./zonai dev
```

If no `zonai.yaml` exists, `zonai dev` prompts you through creating one

## Step 3: Define Tables

Every table's ID is its own type, and they all live in one file. `zonai dev`
creates `lib/src/ids.dart` when it initializes the project, and appends to it
each time you scaffold a table (press `n` in `zonai dev`). Written by hand, the
two IDs this guide needs look like this:

```dart
import 'package:zonai_schema/zonai_schema.dart' as z;

sealed class Id implements z.Id {
  const Id(this.value);

  factory Id.fromJson(String json) {
    final parts = json.split('_');

    if (parts.length != 2) {
      throw ArgumentError('Invalid ID format: $json');
    }

    return switch (parts[1]) {
      TasksId._suffix => TasksId(json),
      UsersId._suffix => UsersId(json),
      _ => throw ArgumentError('Invalid ID format: $json'),
    };
  }

  @override
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  @override
  bool operator ==(Object other) => other is z.Id && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class UsersId extends Id {
  const UsersId(super.value);

  factory UsersId.generate() => UsersId(z.Id.generate(_suffix));

  static const _suffix = 'us';
}

class TasksId extends Id {
  const TasksId(super.value);

  factory TasksId.generate() => TasksId(z.Id.generate(_suffix));

  static const _suffix = 'tk';
}
```

Two details matter here. `zonai_schema` is imported as `z` because its `Id` is
an `abstract interface class` — your base class *implements* it and supplies the
`value` field itself; it cannot `extend` it. And the base is `sealed` so
`Id.fromJson` can switch over every ID in the project exhaustively, which is
what lets a bare string coming off the wire be resolved back to the right type.

Create `lib/src/schemas/users.dart`:

```dart
import 'package:my_app/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class User {
  const User({
    required this.id,
    required this.email,
    required this.passwordHash,
    required this.isVerified,
    required this.createdAt,
    this.updatedAt,
  });

  final UsersId id;
  final String email;
  final String passwordHash;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class UserTable extends AuthTable<User> with PasswordAuth {
  UserTable(super.$)
    : id = $.id('id', (s) => s.id, fromString: UsersId.new, generate: UsersId.generate),
      email = $.email('email', (s) => s.email),
      passwordHash = $.password('password', (s) => s.passwordHash),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  User fromRow(RowReader read) => User(
    id: read(id), email: read(email), passwordHash: read(passwordHash),
    isVerified: read(isVerified),
    createdAt: read(createdAt), updatedAt: read(updatedAt),
  );

  final IdColumn<UsersId> id;
  final EmailColumn email;
  final PasswordColumn passwordHash;
  final IsVerifiedColumn isVerified;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final users = authTable('users', UserTable.new);
```

`PasswordAuth` is what adds the sign-up and sign-in routes, and it requires the
`$.password` column to hash into — an `AuthTable` mixing it in without one will
not compile. `updatedAt` is nullable because `$.updatedAt` only fills in on
write, so a freshly inserted row has none yet.

Create `lib/src/schemas/tasks.dart`:

```dart
import 'package:my_app/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class Task {
  const Task({
    required this.id,
    required this.title,
    required this.isComplete,
    required this.createdAt,
    this.updatedAt,
  });

  final TasksId id;
  final String title;
  final bool isComplete;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class TaskTable extends Table<Task> {
  TaskTable(super.$)
    : id = $.id('id', (s) => s.id, fromString: TasksId.new, generate: TasksId.generate),
      title = $.text('title', (s) => s.title),
      isComplete = $.boolean('is_complete', (s) => s.isComplete),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Task fromRow(RowReader read) => Task(
    id: read(id), title: read(title), isComplete: read(isComplete),
    createdAt: read(createdAt), updatedAt: read(updatedAt),
  );

  final IdColumn<TasksId> id;
  final TextColumn title;
  final BooleanColumn isComplete;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final tasks = table('tasks', TaskTable.new);
```

## Step 4: Configure the App

Create `lib/src/config/db_config.dart`:

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
    jwtSecret: const String.fromEnvironment('JWT_SECRET'),
    passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
    baseUrl: 'http://localhost:8080',
  );
}
```

Create `.env` in the project root:

```
JWT_SECRET=my-dev-jwt-secret-at-least-32-chars
PASSWORD_SECRET=my-dev-password-secret-different-value
```

Add `.env` to `.gitignore`.

## Step 5: Add Access Rules

Create `lib/src/rules/task_table_rules.dart`:

```dart
import 'package:zonai_schema/zonai_schema.dart';
import 'package:my_app/src/schemas/tasks.dart';

final class TaskTableRules extends TableRules<TaskTable, Task> {
  TaskTableRules() : super(tasks);

  @override
  Future<bool> canCreate(Jwt? jwt) async => jwt != null;
  @override
  Future<bool> canList(Jwt? jwt) async => jwt != null;
  @override
  Future<bool> canView(Jwt? jwt) async => jwt != null;
  @override
  Future<bool> canUpdate(Jwt? jwt) async => jwt != null;
  @override
  Future<bool> canDelete(Jwt? jwt) async => jwt != null;
}
```

<Info>

Without a rules file, all operations on a table are denied. Auth endpoints use auth-specific rules (`canSignUp`, `canSignIn`, etc.) in addition to CRUD rules — and they still require a rules file. If you omit it, sign-up and sign-in will be denied.

</Info>

## Step 6: Start the Dev Server

```bash
zonai dev
```

`zonai dev` is the recommended command during development. It starts the server and opens an interactive TUI with helpers for migrations, schema inspection, and more.

To start the server without the TUI, use `zonai serve`. This is useful when you want quieter output or want to replicate a closer-to-production environment while still in development.

## Step 7: Make API Calls

**Sign up:**

```bash
curl -X POST http://localhost:8080/auth/sign-up \
  -H "Content-Type: application/json" \
  -d '{"type":"signUp","table":"users","email":"alice@example.com","password":"hunter2"}'
```

**Sign in:**

```bash
curl -X POST http://localhost:8080/auth/sign-in \
  -H "Content-Type: application/json" \
  -d '{"type":"signIn","table":"users","email":"alice@example.com","password":"hunter2"}'
```

The response includes `data.accessToken`. Use it for subsequent requests. The table name is always in the JSON body — never in the URL path.

```bash
TOKEN="eyJ..."

# Create a task
curl -X POST http://localhost:8080/db \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"table":"tasks","object":{"title":"Buy groceries","isComplete":false}}'

# List tasks
curl -G http://localhost:8080/db/list \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'body={"table":"tasks","limit":20}'
```

## Step 8: Stream Live Updates

Zonai pushes query results over a long-lived HTTP connection whenever rows change. In Dart apps use `zonai_client` → `client.db.listen` (see [Streaming](/operations/streaming)).

```bash
# Keep this curl open — a new JSON payload arrives when matching rows change
curl -N -G http://localhost:8080/db/stream/list \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'body={"table":"tasks","where":{"isComplete":{"eq":false}},"limit":20}'
```

<Info>

Every table gets `/db/stream`, `/db/stream/list`, and `/db/stream/count` automatically.

</Info>

## Next Steps

- [Live Queries (Streaming)](/operations/streaming) — `client.db.listen` and stream endpoints
- [Project Structure](/getting-started/project-structure) — understand what each directory does
- [Schemas](/schemas/defining-tables) — all column types and modifiers
- [Rules](/rules/overview) — fine-grained authorization
- [Dart Client](/dart-client/overview) — typed client including `db.listen`
