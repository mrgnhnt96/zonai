---
title: Quick Start
description: Build and run your first Zonai project from scratch in under 10 minutes.
---

This guide walks through creating a small REST API with a `users` auth table and a `tasks` table. By the end you will have a running server and be able to sign up, sign in, and create tasks.

## Step 1: Create a Dart Project

```bash
dart create my_app && cd my_app
```

Add Zonai to `pubspec.yaml`:

```yaml
dependencies:
  zonai_schema: ^0.1.0

dev_dependencies:
  zonai: ^0.1.0
```

Run `dart pub get`.

## Step 2: Initialize Zonai

```bash
zonai dev
```

If no `zonai.yaml` exists, `zonai dev` prompts you through creating one

## Step 3: Define Tables

Create `lib/src/schemas/users.dart`:

```dart
import 'package:zonai_schema/zonai_schema.dart';

final class User {
  const User({
    required this.id,
    required this.email,
    required this.isVerified,
    required this.createdAt,
    required this.updatedAt,
  });

  final UsersId id;
  final String email;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class UsersId extends Id {
  const UsersId(super.value);
  factory UsersId.generate() => UsersId(Id.generate('us'));
}

final class UserTable extends AuthTable<User> with PasswordAuth {
  UserTable(super.$)
    : id = $.id('id', (s) => s.id, fromString: UsersId.new, generate: UsersId.generate),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  User fromRow(RowReader read) => User(
    id: read(id), email: read(email), isVerified: read(isVerified),
    createdAt: read(createdAt), updatedAt: read(updatedAt),
  );

  final IdColumn<UsersId> id;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final CreatedAtColumn createdAt;
  final UpdatedAtColumn updatedAt;
}

final users = authTable('users', UserTable.new);
```

Create `lib/src/schemas/tasks.dart`:

```dart
import 'package:zonai_schema/zonai_schema.dart';

final class Task {
  const Task({
    required this.id,
    required this.title,
    required this.isComplete,
    required this.createdAt,
    required this.updatedAt,
  });

  final TasksId id;
  final String title;
  final bool isComplete;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class TasksId extends Id {
  const TasksId(super.value);
  factory TasksId.generate() => TasksId(Id.generate('tk'));
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
  final BoolColumn isComplete;
  final CreatedAtColumn createdAt;
  final UpdatedAtColumn updatedAt;
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

The response includes `data.accessToken`. Use it for subsequent requests:

```bash
TOKEN="eyJ..."

# Create a task
curl -X POST http://localhost:8080/db/tasks \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Buy groceries","isComplete":false}'

# List tasks
curl http://localhost:8080/db/tasks/list \
  -H "Authorization: Bearer $TOKEN"
```

## Next Steps

- [Project Structure](/getting-started/project-structure) — understand what each directory does
- [Schemas](/schemas/defining-tables) — all column types and modifiers
- [Rules](/rules/overview) — fine-grained authorization
