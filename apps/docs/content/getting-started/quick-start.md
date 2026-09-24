---
title: Quick Start
description: Build and run your first Zonai project from scratch in under 10 minutes.
---

Build a small API with a `users` auth table and a `tasks` table, call it, open the dashboard, and build it for production. You need the Dart SDK installed. [Installation](/getting-started/installation) lists the requirements.

## 1. Create the project

Start in an empty folder, with the binary in it:

```bash
mkdir my_app && cd my_app
curl -fsSL https://github.com/mrgnhnt96/zonai/releases/latest/download/zonai -o zonai
chmod +x zonai
./zonai dev
```

On Windows, use `zonai.exe` from the [Windows zip](/getting-started/installation#install-the-cli) instead of `curl`.

With no `zonai.yaml` present, `zonai dev` asks `Initialize project? [Y/n]`. Answer yes, and it:

- writes `pubspec.yaml` (depending on `zonai_schema`) and runs `dart pub get`
- writes `zonai.yaml`, and adds a few runtime files to `.gitignore`
- scaffolds `lib/src/`: `ids.dart`, an `admins` auth table with its rules and operations, `config/db_config.dart` with freshly generated JWT and password secrets, and the built-in email templates
- compiles the workers, then opens the dev TUI and starts the server on **http://localhost:8080**

The TUI stays open while you work. Its menu shows a key for each action. The ones this guide uses are **`n`** (create schema), **`m`** (generate migration), **`u`** (apply migrations), **`a`** (create admin), and **`s`** (start/stop the server). `q` quits. If you want the server without the TUI, run `./zonai serve` instead. [Project Structure](/getting-started/project-structure) explains every file.

## 2. Add tables

Every table has its own ID type in `lib/src/ids.dart`. Pressing **`n`** in the TUI scaffolds a schema file and adds its ID type for you. To do it by hand, add a case to the `switch` in `Id.fromJson` and a class for each new table:

```dart no-analyze
// lib/src/ids.dart — additions only. Keep the existing Id base and AdminsId.
//   in Id.fromJson's switch:
//     TasksId._suffix => TasksId(json),
//     UsersId._suffix => UsersId(json),

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

(That fence is not analyzed because it is a fragment of an existing file.)

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

`PasswordAuth` adds the sign-up and sign-in routes and requires a `$.password` column to hash into. `updatedAt` is nullable because `$.updatedAt` is only filled on update.

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

The first argument to each `$.column(...)` call is the database column name. That name, `is_complete` for example, is also the JSON key over HTTP.

## 3. Open the tables with rules

A table with no rules refuses every request, even an admin's. Each table needs a **table rules** file and a **row rules** file under `lib/src/rules/`. Each file must have a top-level `main()` that returns the rules object, because that is how Zonai loads it.

For `users`, the defaults already allow password sign-up and sign-in, so the files only need to exist:

```dart
// lib/src/rules/user_table_rules.dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserTableRules main() => UserTableRules();

final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);
}
```

```dart
// lib/src/rules/user_row_rules.dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

UserRowRules main() => UserRowRules();

final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);
}
```

For `tasks`, let any signed-in user do anything:

```dart
// lib/src/rules/task_table_rules.dart
import 'package:my_app/src/schemas/tasks.dart';
import 'package:zonai_schema/zonai_schema.dart';

TaskTableRules main() => TaskTableRules();

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

```dart
// lib/src/rules/task_row_rules.dart
import 'package:my_app/src/schemas/tasks.dart';
import 'package:zonai_schema/zonai_schema.dart';

TaskRowRules main() => TaskRowRules();

final class TaskRowRules extends RowRules<TaskTable, Task> {
  TaskRowRules() : super(tasks);

  @override
  Future<bool> canView(Jwt? jwt, Task row) async => jwt != null;
  @override
  Future<bool> canCreate(Jwt? jwt, Task row) async => jwt != null;
  @override
  Future<bool> canUpdate(Jwt? jwt, Task before, Task after) async => jwt != null;
  @override
  Future<bool> canDelete(Jwt? jwt, Task row) async => jwt != null;
}
```

A real app checks ownership in the row rules. See [Row Rules](/rules/row-rules).

## 4. Migrate and restart

In the TUI, press **`m`** and name the migration (for example `add_users_and_tasks`), then **`u`** to apply it, then **`s`** twice to restart the server. The same thing from a second terminal:

```bash
./zonai db migrate generate --name add_users_and_tasks
./zonai db migrate apply
```

Migration files land in `.zonai/migrations/`. Commit them.

## 5. Call the API

The table name always goes in the JSON body, never in the URL.

```bash
# Sign up. Returns { "data": { "accessToken": "...", "user": { ... } } }
curl -X POST http://localhost:8080/auth/sign-up \
  -H "Content-Type: application/json" \
  -d '{"type":"signUp","table":"users","email":"alice@example.com","password":"hunter2"}'

# Sign in. Same response shape
curl -X POST http://localhost:8080/auth/sign-in \
  -H "Content-Type: application/json" \
  -d '{"type":"signIn","table":"users","email":"alice@example.com","password":"hunter2"}'

TOKEN="<data.accessToken from above>"

# Create a task
curl -X POST http://localhost:8080/db \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"table":"tasks","object":{"title":"Buy groceries","is_complete":false}}'

# List tasks (GET bodies go in ?body=)
curl -G http://localhost:8080/db/list \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'body={"table":"tasks","limit":20}'

# Live query: the connection stays open and prints a new result whenever matching rows change
curl -N -G http://localhost:8080/db/stream/list \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'body={"table":"tasks","where":{"is_complete":{"eq":false}},"limit":20}'
```

From Dart or Flutter, use [`zonai_client`](/dart-client/overview) (`dart pub add zonai_client` in the *app*, not the server project). It stores the token after sign-in and sends it on every call:

```dart
import 'package:zonai_client/zonai_client.dart';

Future<void> main() async {
  final client = ZonaiClient(baseUrl: Uri.parse('http://localhost:8080'));

  await client.auth.signIn(
    body: SignInAuthBody(table: 'users', email: 'alice@example.com', password: 'hunter2'),
  );

  await client.db.create(
    body: CreateBody(table: 'tasks', object: {'title': 'Buy groceries', 'is_complete': false}),
    fromJson: (row) => row,
  );

  client.db.listen
      .list(body: StreamListBody(table: 'tasks'), fromJson: (row) => row)
      .listen((rows) => print('${rows.length} tasks'));
}
```

For typed per-table methods such as `client.tasks.list()`, generate them with [`zonai gen client`](/dart-client/typed-client).

## 6. Open the dashboard

Every server serves an admin UI at **http://localhost:8080/_**. Signing in needs an account in the scaffolded `admins` table. Press **`a`** in the TUI, or run:

```bash
./zonai db admin add --email you@example.com --password 'a-long-password'
```

See [Dashboard Overview](/dashboard/overview) before exposing `/_` publicly.

## 7. Build for production

```bash
./zonai build --release
```

This writes `build/`, which holds the server binary, compiled workers, migrations, email templates, and `zonai.yaml`. Copy the folder to the server and run it from inside:

```bash
cd build && ./zonai serve --release --host 0.0.0.0 --port 8080
```

`--release` turns Dart asserts off in the build. At serve time it disables file watching and recompiling. The server applies any pending migrations shipped in `build/` when it opens the database, but it never generates new ones. By default the server listens only on loopback (`127.0.0.1`), so pass `--host` or set `host:` in `zonai.yaml` to accept outside traffic. The scaffold compiles its secrets into the binary. To keep them out, set `JWT_SECRET` and `PASSWORD_SECRET` in the server's environment, and those values take precedence. Next, read [Building for Production](/deployment/building-for-production) and [Running the Server](/deployment/running-the-server).

## Next Steps

- [Project Structure](/getting-started/project-structure) — what each file does and what to commit
- [Schemas](/schemas/defining-tables) — every column type and modifier
- [Rules](/rules/overview) — ownership checks and admin-only access
- [Live Queries](/operations/streaming) — `/db/stream*` and `client.db.listen`
