/// Template strings for AI coding assistant reference files.
library;

// ---------------------------------------------------------------------------
// Shared master reference document (used by Claude, Copilot, Windsurf, Cline)
// ---------------------------------------------------------------------------

const _doc = r"""
# Zonai Framework Reference

Zonai is a Dart CLI framework that compiles your declarative Dart code into
worker executables and runs a SQLite-backed REST API server. You write schemas,
rules, operations, extensions, rate limits, and crons — Zonai generates the SQL
and handles HTTP.

**Worker compile model**: `zonai compile` builds five workers from your source:
`db_operations`, `db_rules`, `db_extensions`, `db_rate_limit`, `db_crons`. The
server calls these executables per request. Workers auto-recompile on file
changes during `zonai serve`.

---

## Project structure

```
my_app/
  zonai.yaml              # project config (paths, version)
  pubspec.yaml
  lib/src/
    ids.dart              # typed ID classes (one per table)
    schemas/              # Table + entity class definitions
    config/               # AppConfig (SMTP, JWT, base URL, photos)
    operations/           # optional: custom CRUD SQL overrides per table
    rules/                # authorization — table + row rules per collection
    extensions/           # lifecycle hooks (create/update/delete/auth)
    rate_limit/           # per-operation request throttling
    crons/                # scheduled background jobs
    email_templates/      # HTML email template files
  .zonai/
    migrations/           # SQL migration files (managed by zonai db migrate)
```

### zonai.yaml

```yaml
version: 1.0.0
migrationsPath: .zonai/migrations
schemasPath:    lib/src/schemas
configPath:     lib/src/config
emailTemplatesPath: lib/src/email_templates
rulesPath:      lib/src/rules
operationsPath: lib/src/operations
extensionsPath: lib/src/extensions
rateLimitPath:  lib/src/rate_limit
cronsPath:      lib/src/crons
```

---

## Schemas

Every table needs an entity class (plain Dart) and a table class extending
`Table<R>` (regular) or `AuthTable<R>` (auth). Expose via top-level `final`
using `table()` or `authTable()`.

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../ids.dart';

class Item {
  Item({
    required this.id,
    required this.body,
    required this.createdAt,
    this.description,
    this.updatedAt,
  });

  final ItemsId id;
  final String body;
  final String? description;  // nullable = optional column
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class ItemTable extends Table<Item> {
  ItemTable(super.$)
    : id = $.id('id', (s) => s.id,
          fromString: ItemsId.new, generate: ItemsId.generate),
      body = $.text('body', (s) => s.body),
      description = $.text('description', (s) => s.description),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Item fromRow(RowReader read) => Item(
    id: read(id), body: read(body), description: read(description),
    createdAt: read(createdAt), updatedAt: read(updatedAt),
  );

  final IdColumn<ItemsId> id;
  final TextColumn body;
  final TextColumn? description;
  final DateTimeColumn createdAt;
  final DateTimeColumn? updatedAt;
}

final items = table('items', ItemTable.new);
```

### Column helpers

| Helper | Column type | Notes |
|--------|-------------|-------|
| `$.id(name, getter, fromString:, generate:)` | `IdColumn<T>` | Typed ID class |
| `$.text(name, getter)` | `TextColumn` | |
| `$.integer(name, getter)` | `IntColumn` | |
| `$.boolean(name, getter)` | `BoolColumn` | |
| `$.decimal(name, getter)` | `DecimalColumn` | |
| `$.email(name, getter)` | `EmailColumn` | Auth tables |
| `$.password(name, getter)` | `PasswordColumn` | Auth tables; Argon2id auto-hashed |
| `$.photo(name, getter)` | `PhotoColumn` | Stores `PhotoId?` |
| `$.createdAt(name, getter)` | `DateTimeColumn` | Auto-set on insert |
| `$.updatedAt(name, getter)` | `DateTimeColumn?` | Auto-set on update |
| `$.isVerified(name, getter)` | `IsVerifiedColumn` | Auth tables |

Nullable getter type (`String?`) → nullable SQL column.

### Auth tables

```dart
final class UserTable extends AuthTable<User>
    with PasswordAuth, OtpAuth, MagicLinkAuth, AsAdmin {
  UserTable(super.$)
    : id = $.id('id', (s) => s.id,
          fromString: UsersId.new, generate: UsersId.generate),
      name = $.text('name', (s) => s.name),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  User fromRow(RowReader read) => User(
    id: read(id), name: read(name), email: read(email),
    isVerified: read(isVerified), passwordHash: read(passwordHash),
    createdAt: read(createdAt), updatedAt: read(updatedAt),
  );

  final IdColumn<UsersId> id;
  final TextColumn name;
  final EmailColumn email;
  final IsVerifiedColumn isVerified;
  final PasswordColumn passwordHash;
  final DateTimeColumn createdAt;
  final DateTimeColumn? updatedAt;
}

final users = authTable('users', UserTable.new);
```

Auth mixins: `PasswordAuth`, `OtpAuth`, `MagicLinkAuth`. Add `AsAdmin` to allow
users of this table to authenticate as admins.

### ID classes (`lib/src/ids.dart`)

```dart
import 'package:zonai_schema/zonai_schema.dart' as z;

class ItemsId implements z.Id {
  const ItemsId(this.value);
  factory ItemsId.generate() => ItemsId(z.Id.generate('it')); // short suffix
  factory ItemsId.new(String v) => ItemsId(v);
  final String value;
  @override String toString() => value;
  @override bool operator ==(Object o) => o is ItemsId && o.value == value;
  @override int get hashCode => value.hashCode;
}
```

Use a unique 2-3 char suffix per table (e.g. `'it'` for items, `'us'` for users).
IDs are formatted as `<timestamp>_<suffix>`.

---

## Operations

Operations are optional — default CRUD SQL is auto-generated for all tables.
Add an operations file only to customize SQL or add custom JWT claims.

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../schemas/users.dart';

final class UserOperations extends TableOperations<UserTable, User>
    with AuthOperations {
  UserOperations() : super(users);

  @override
  Future<Claims> addClaims({required Jwt jwt}) async {
    return Claims({'role': 'member'});
  }
}

UserOperations main() => UserOperations();
```

`AuthOperations` mixin adds:

| Override | Purpose |
|----------|---------|
| `addClaims({required Jwt jwt})` | Extra JWT claims merged into tokens |
| `jwtExpiresIn` | Per-collection JWT lifetime override |
| `magicLinkConfig` | Magic-link path + expiry |
| `resetPasswordConfig` | Reset-password path + expiry |
| `verifyEmailConfig` | Verify-email path + expiry |

One file per collection. Each file's `main()` must return a `TableOperations` instance.

---

## Rules

Every collection you expose through the API needs rules. Default: deny all
non-admin access.

### Table rules (collection-level)

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../schemas/items.dart';

final class ItemTableRules extends TableRules<ItemTable, Item> {
  ItemTableRules() : super(items);

  @override Future<bool> canCreate(Jwt? jwt) async => jwt != null;
  @override Future<bool> canList(Jwt? jwt) async => true;
  @override Future<bool> canView(Jwt? jwt) async => true;
  @override Future<bool> canUpdate(Jwt? jwt) async => jwt?.admin.canEdit == true;
  @override Future<bool> canDelete(Jwt? jwt) async => jwt?.admin.canEdit == true;
}

ItemTableRules main() => ItemTableRules();
```

### Row rules (per-record)

```dart
class ItemRowRules extends RowRules<ItemTable, Item> {
  ItemRowRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt, Item row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Item row) async {
    if (jwt?.admin.canEdit == true) return true;
    return jwt?.userId.value == row.ownerId.value;
  }

  @override Future<bool> canCreate(Jwt? jwt, Item row) async => jwt != null;
  @override Future<bool> canDelete(Jwt? jwt, Item row) async =>
      jwt?.admin.canEdit == true;
}

ItemRowRules main() => ItemRowRules();
```

### Auth rules

```dart
final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);
  // canAuthenticate(Jwt? jwt, AuthType type) — default: true
}
UserTableRules main() => UserTableRules();

class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);
  // canSignUp(Jwt? jwt, User user), canSignIn(...), canPasswordReset(...)
}
UserRowRules main() => UserRowRules();
```

Base class pairs: `TableRules`/`RowRules` (regular), `AuthTableRules`/`AuthRowRules` (auth).

### JWT fields

| Field | Purpose |
|-------|---------|
| `jwt?.userId` | Authenticated user ID |
| `jwt?.collection` | Auth collection name |
| `jwt?.claims['key']` | Custom claims from `addClaims` |
| `jwt?.admin.isAdmin` | Admin read access |
| `jwt?.admin.canEdit` | Admin write access |

Rules use server-checks: table rules first, then row rules. If either denies,
request is rejected with a permissions error.

---

## Extensions

Lifecycle hooks around mutations and auth events.

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../schemas/items.dart';

class ItemExtensions extends Extension<Item>
    with CreateExtension, UpdateExtension, DeleteExtension {
  ItemExtensions() : super(items);

  @override
  Future<void> beforeCreate(Item object, Jwt? jwt) async {
    logger.debug('Creating ${object.id}');
  }

  @override
  Future<void> afterCreateSuccess(Item object, Jwt? jwt) async {
    mutate.update.one(
      collection: 'items',
      updates: [Update.column('body', .literal('processed'))],
      where: Eq('id', object.id),
    );
  }

  @override
  Future<void> afterCreateError(Object error, Jwt? jwt) async {}

  @override
  Future<void> beforeUpdate(Item row, Jwt? jwt) async {}

  @override
  Future<void> afterUpdateSuccess(Item before, Item after, Jwt? jwt) async {}

  @override
  Future<void> afterUpdateError(Object error, Jwt? jwt) async {}

  @override
  Future<void> beforeDelete(Item row, Jwt? jwt) async {}

  @override
  Future<void> afterDeleteSuccess(Item row, Jwt? jwt) async {}

  @override
  Future<void> afterDeleteError(Object error, Jwt? jwt) async {}
}

ItemExtensions main() => ItemExtensions();
```

Mixins: `CreateExtension`, `UpdateExtension`, `DeleteExtension`, `AuthExtension`.

`AuthExtension` hooks: `onSignUp(R user, Jwt? jwt)`, `onSignIn`, `onRefresh`,
`onLogout`.

### Side effect globals (from `package:zonai_schema/zonai_schema.dart`)

| Global | Purpose |
|--------|---------|
| `get.one(collection:, where:)` | Read a single row |
| `get.many(collection:, where:)` | Read multiple rows |
| `mutate.create.one(collection:, values:)` | Queue a create |
| `mutate.update.one(collection:, updates:, where:)` | Queue an update |
| `mutate.delete.many(tableName:, updates:, where:)` | Queue deletes |
| `email.send.verifyEmail(...)` | Send verify-email link |
| `email.send.loginNotice(...)` | Send login notification |
| `logger.debug/info/warn/error(msg)` | Log to server console |

Writes via `mutate` are queued and committed after the main mutation, going
through rules+extensions again (up to 10 chained iterations).

---

## Rate Limits

Optional — default is 100 requests per minute per IP per collection+operation.
Return `null` from any policy method to disable limiting for that operation.

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../schemas/items.dart';

final class ItemRateLimits extends TableRateLimits<ItemTable, Item> {
  ItemRateLimits() : super(items);

  @override
  Future<RateLimitPolicy?> getPolicy() async =>
      const RateLimitPolicy(maxRequests: 100, window: Duration(minutes: 1));

  @override
  Future<RateLimitPolicy?> limitPolicy() async =>
      const RateLimitPolicy(maxRequests: 50, window: Duration(minutes: 1));

  @override
  Future<RateLimitPolicy?> createPolicy() async => null; // unlimited
}

ItemRateLimits main() => ItemRateLimits();
```

Data policy methods: `getPolicy`, `limitPolicy`, `countPolicy`, `createPolicy`,
`updatePolicy`, `deletePolicy`.

Auth policy methods (on `AuthTableRateLimits`): `signInPolicy`, `signUpPolicy`,
`refreshTokenPolicy`, `sendResetPasswordPolicy`, `sendVerifyEmailPolicy`, etc.

---

## Crons

Scheduled background jobs. Each file returns a `CronJob` via `main()`.

```dart
import 'package:cron/cron.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class CleanupLogsJob extends CronJob {
  const CleanupLogsJob()
    : super(
        name: 'cleanup_logs',           // unique snake_case identifier
        schedule: Schedule.parse('0 3 * * *'), // daily at 03:00
      );

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    mutate.delete.many(
      tableName: 'logs',
      updates: [],
      where: Lt('created_at', cutoff),
    );
    logger.info('Queued log cleanup older than $cutoff');
  }
}

CleanupLogsJob main() => const CleanupLogsJob();
```

| Property | Default | Purpose |
|----------|---------|---------|
| `name` | required | Unique snake_case job identifier |
| `schedule` | required | `Schedule.parse('* * * * *')` (5-field cron) |
| `strict` | `true` | Skip missed runs when server was down |
| `runOnStartup` | `false` | Run once immediately when crons start |

Cron jobs access the same `get`, `mutate`, `email`, `logger` globals as
extensions. Runs under `CronJwt` (internal admin-level identity).

---

## Config

Single file under `configPath` returns `AppConfig` via `main()`:

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    applicationName: 'My App',
    passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
    jwtSecret: const String.fromEnvironment('JWT_SECRET'),
    baseUrl: 'http://localhost:8080',
    email: EmailConfig(
      host: 'smtp.example.com',
      port: 587,
      username: 'user@example.com',
      password: const String.fromEnvironment('SMTP_PASSWORD'),
      from: EmailAddress(address: 'noreply@example.com', name: 'My App'),
    ),
    photos: PhotosConfig(maxBytes: 5 * 1024 * 1024),
  );
}
```

---

## CLI Commands

```
dart run zonai build       # compile workers + package binary for deployment
dart run zonai serve       # start HTTP server with file-watching + auto-recompile
dart run zonai dev         # interactive TUI (compile, serve, logs, schema scaffold)
dart run zonai compile     # compile all workers only
dart run zonai db migrate  # run SQL migrations
dart run zonai db admin    # manage admin accounts
dart run zonai rules       # inspect compiled authorization rules
dart run zonai ping        # test worker executables
dart run zonai version     # show version + check for updates
```

---

## Generated workers

`zonai compile` produces executables in `.zonai/executables/`:
- `db_operations.exe` — SQL generation
- `db_rules.exe` — authorization
- `db_extensions.exe` — lifecycle hooks
- `db_rate_limit.exe` — rate limiting
- `db_crons.exe` — scheduled jobs

Intermediate Dart sources written to `.dart_tool/zonai/` before compilation.
""";

// ---------------------------------------------------------------------------
// Single-file tool templates
// ---------------------------------------------------------------------------

const claudeMd = r"""# Zonai Project

This is a **zonai** application. Zonai is a Dart CLI framework that compiles
your Dart code into worker executables and runs a SQLite-backed REST API.

Use `dart run zonai dev` to launch the interactive TUI, or
`dart run zonai serve` to start the server with auto-recompile on file changes.

""" + _doc;

const copilotMd = _doc;
const windsurfRules = _doc;
const clineRules = _doc;

// ---------------------------------------------------------------------------
// Cursor MDC files — one per topic, with glob-based auto-attachment
// ---------------------------------------------------------------------------

const cursorOverviewMdc = r"""---
description: zonai overview — framework, project layout, CLI commands, zonai.yaml config
globs: zonai.yaml
alwaysApply: false
---

# Zonai Framework Overview

Zonai is a Dart CLI framework that compiles declarative Dart code into worker
executables and runs a SQLite-backed REST API server.

**Worker compile model**: `zonai compile` builds five workers from your source:
- `db_operations` — custom CRUD SQL (`lib/src/operations/`)
- `db_rules` — authorization decisions (`lib/src/rules/`)
- `db_extensions` — lifecycle hooks (`lib/src/extensions/`)
- `db_rate_limit` — rate limiting (`lib/src/rate_limit/`)
- `db_crons` — scheduled jobs (`lib/src/crons/`)

The server calls these executables per request. Workers auto-recompile on
file changes during `zonai serve`.

## Project structure

```
my_app/
  zonai.yaml              # project config
  lib/src/
    ids.dart              # typed ID classes (one per table)
    schemas/              # Table + entity class definitions
    config/               # AppConfig (SMTP, JWT, base URL, photos)
    operations/           # optional CRUD SQL overrides
    rules/                # authorization per collection
    extensions/           # lifecycle hooks
    rate_limit/           # request throttling
    crons/                # scheduled jobs
    email_templates/      # HTML email files
  .zonai/
    migrations/           # SQL migration files
```

## zonai.yaml

```yaml
version: 1.0.0
migrationsPath: .zonai/migrations
schemasPath:    lib/src/schemas
configPath:     lib/src/config
emailTemplatesPath: lib/src/email_templates
rulesPath:      lib/src/rules
operationsPath: lib/src/operations
extensionsPath: lib/src/extensions
rateLimitPath:  lib/src/rate_limit
cronsPath:      lib/src/crons
```

## CLI Commands

```
dart run zonai build       # compile workers + package for deployment
dart run zonai serve       # start server with file-watching + auto-recompile
dart run zonai dev         # interactive TUI
dart run zonai compile     # compile all workers only
dart run zonai db migrate  # run SQL migrations
dart run zonai rules       # inspect compiled authorization rules
dart run zonai ping        # test worker executables
dart run zonai version     # show version
```

## Config (`lib/src/config/`)

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    applicationName: 'My App',
    passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
    jwtSecret: const String.fromEnvironment('JWT_SECRET'),
    baseUrl: 'http://localhost:8080',
    email: EmailConfig(
      host: 'smtp.example.com',
      port: 587,
      username: 'user@example.com',
      password: const String.fromEnvironment('SMTP_PASSWORD'),
      from: EmailAddress(address: 'noreply@example.com', name: 'My App'),
    ),
    photos: PhotosConfig(maxBytes: 5 * 1024 * 1024),
  );
}
```
""";

const cursorSchemasMdc = r"""---
description: zonai schemas — Table/AuthTable classes, column helpers, ID classes, entity types
globs: lib/src/schemas/**
alwaysApply: false
---

# Zonai Schemas

Schemas live under `schemasPath` (default `lib/src/schemas`). Each file defines
an entity class (plain Dart) and a table class extending `Table<R>` or
`AuthTable<R>`. Expose via a top-level `final` using `table()` or `authTable()`.

## Regular table

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../ids.dart';

class Item {
  Item({
    required this.id,
    required this.body,
    required this.createdAt,
    this.description,
    this.updatedAt,
  });

  final ItemsId id;
  final String body;
  final String? description;  // nullable type = nullable column
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class ItemTable extends Table<Item> {
  ItemTable(super.$)
    : id = $.id('id', (s) => s.id,
          fromString: ItemsId.new, generate: ItemsId.generate),
      body = $.text('body', (s) => s.body),
      description = $.text('description', (s) => s.description),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Item fromRow(RowReader read) => Item(
    id: read(id), body: read(body), description: read(description),
    createdAt: read(createdAt), updatedAt: read(updatedAt),
  );

  final IdColumn<ItemsId> id;
  final TextColumn body;
  final TextColumn? description;
  final DateTimeColumn createdAt;
  final DateTimeColumn? updatedAt;
}

final items = table('items', ItemTable.new);
```

## Auth table

```dart
final class UserTable extends AuthTable<User>
    with PasswordAuth, OtpAuth, MagicLinkAuth, AsAdmin {
  UserTable(super.$)
    : id = $.id('id', (s) => s.id,
          fromString: UsersId.new, generate: UsersId.generate),
      name = $.text('name', (s) => s.name),
      email = $.email('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified),
      passwordHash = $.password('password', (s) => s.passwordHash),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  User fromRow(RowReader read) => User(
    id: read(id), name: read(name), email: read(email),
    isVerified: read(isVerified), passwordHash: read(passwordHash),
    createdAt: read(createdAt), updatedAt: read(updatedAt),
  );

  // ... field declarations ...
}

final users = authTable('users', UserTable.new);
```

Auth mixins: `PasswordAuth`, `OtpAuth`, `MagicLinkAuth`. Add `AsAdmin` to allow
users of this table to authenticate as admins.

## Column helpers

| Helper | Column type | Notes |
|--------|-------------|-------|
| `$.id(name, getter, fromString:, generate:)` | `IdColumn<T>` | Typed ID |
| `$.text(name, getter)` | `TextColumn` | |
| `$.integer(name, getter)` | `IntColumn` | |
| `$.boolean(name, getter)` | `BoolColumn` | |
| `$.decimal(name, getter)` | `DecimalColumn` | |
| `$.email(name, getter)` | `EmailColumn` | Auth tables |
| `$.password(name, getter)` | `PasswordColumn` | Auto-hashed (Argon2id) |
| `$.photo(name, getter)` | `PhotoColumn` | Stores `PhotoId?` |
| `$.createdAt(name, getter)` | `DateTimeColumn` | Auto-set on insert |
| `$.updatedAt(name, getter)` | `DateTimeColumn?` | Auto-set on update |
| `$.isVerified(name, getter)` | `IsVerifiedColumn` | Auth tables |

Nullable getter (`String?`) → nullable column in SQL.

## ID classes (`lib/src/ids.dart`)

```dart
import 'package:zonai_schema/zonai_schema.dart' as z;

class ItemsId implements z.Id {
  const ItemsId(this.value);
  factory ItemsId.generate() => ItemsId(z.Id.generate('it'));
  factory ItemsId.new(String v) => ItemsId(v);
  final String value;
  @override String toString() => value;
  @override bool operator ==(Object o) => o is ItemsId && o.value == value;
  @override int get hashCode => value.hashCode;
}
```

Use a unique 2-3 char suffix per table. IDs are `<timestamp>_<suffix>`.
""";

const cursorOperationsMdc = r"""---
description: zonai operations — TableOperations, AuthOperations, custom CRUD SQL, JWT claims
globs: lib/src/operations/**
alwaysApply: false
---

# Zonai Operations

Operations are **optional** — default CRUD SQL is auto-generated for every
table in `schemasPath`. Add a file under `operationsPath` only to:
- Override SQL for specific operations
- Add custom JWT claims on auth collections

Each file's `main()` returns one `TableOperations` instance:

## Regular collection (no customization needed)

Most collections need no operations file. The schema alone is enough.

## Auth collection with custom JWT claims

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../schemas/users.dart';

final class UserOperations extends TableOperations<UserTable, User>
    with AuthOperations {
  UserOperations() : super(users);

  @override
  Future<Claims> addClaims({required Jwt jwt}) async {
    return Claims({'role': 'member', 'verified': jwt.user['is_verified']});
  }
}

UserOperations main() => UserOperations();
```

## `AuthOperations` overrides

| Override | Purpose |
|----------|---------|
| `addClaims({required Jwt jwt})` → `Future<Claims>` | Extra JWT claims |
| `jwtExpiresIn` → `Duration?` | Per-collection JWT lifetime (`null` = use AppConfig) |
| `magicLinkConfig` → `MagicLinkConfig?` | Magic-link URL path + expiry |
| `resetPasswordConfig` → `ResetPasswordConfig?` | Reset-password URL path + expiry |
| `verifyEmailConfig` → `VerifyEmailConfig?` | Verify-email URL path + expiry |

## Custom SQL operations

Override `TableOperations` methods to customize SQL:

```dart
@override
rd.ToQuery<PostTable, Post> custom(
  String operation, {
  Where? where,
  Map<String, dynamic>? values,
}) {
  return switch (operation) {
    'archive' => db
        .update(posts)
        .setAll([UpdateableColumn(table['archived'], true)])
        .where(RawSqlFilter(where!.sql(table.name)))
        .toQuery(),
    _ => super.custom(operation, where: where, values: values),
  };
}
```

One file per collection. `main()` must return a non-null `TableOperations`.
""";

const cursorRulesMdc = r"""---
description: zonai rules — TableRules, RowRules, AuthTableRules, AuthRowRules, JWT access control
globs: lib/src/rules/**
alwaysApply: false
---

# Zonai Rules

Rules decide whether a request is allowed. Every collection you expose needs
**two files**: one table-rules file and one row-rules file. Default behavior:
deny all non-admin access.

Rules run **before** SQL. If denied, the server rejects with a permissions error.

## Table rules (collection-level check)

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../schemas/items.dart';

final class ItemTableRules extends TableRules<ItemTable, Item> {
  ItemTableRules() : super(items);

  @override Future<bool> canCreate(Jwt? jwt) async => jwt != null;
  @override Future<bool> canList(Jwt? jwt) async => true;
  @override Future<bool> canView(Jwt? jwt) async => true;
  @override Future<bool> canUpdate(Jwt? jwt) async => jwt?.admin.canEdit == true;
  @override Future<bool> canDelete(Jwt? jwt) async => jwt?.admin.canEdit == true;
}

ItemTableRules main() => ItemTableRules();
```

## Row rules (per-record check)

Receives the typed row so you can inspect column values:

```dart
class ItemRowRules extends RowRules<ItemTable, Item> {
  ItemRowRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt, Item row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Item row) async {
    if (jwt?.admin.canEdit == true) return true;
    return jwt?.userId.value == row.ownerId.value;
  }

  @override Future<bool> canCreate(Jwt? jwt, Item row) async => jwt != null;
  @override Future<bool> canDelete(Jwt? jwt, Item row) async =>
      jwt?.admin.canEdit == true;
}

ItemRowRules main() => ItemRowRules();
```

## Auth collection rules

```dart
final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);
  // canAuthenticate(Jwt? jwt, AuthType type) → bool — default: true
}
UserTableRules main() => UserTableRules();

class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);
  // canSignUp(Jwt? jwt, User user), canSignIn(...), canPasswordReset(...)
  // Row CRUD defaults: user can view/modify own row; admins have elevated access
}
UserRowRules main() => UserRowRules();
```

Base class pairs:
- Regular: `TableRules<S, R>` / `RowRules<S, R>`
- Auth: `AuthTableRules<S, R>` / `AuthRowRules<S, R>`

## JWT fields

| Field | Purpose |
|-------|---------|
| `jwt?.userId` | Authenticated user ID |
| `jwt?.collection` | Auth collection name |
| `jwt?.claims['key']` | Custom claims from `addClaims` |
| `jwt?.user` | User row snapshot at token issuance |
| `jwt?.admin.isAdmin` | Admin read access |
| `jwt?.admin.canEdit` | Admin write access |

`jwt == null` means unauthenticated. Deny by default unless you explicitly
return `true` for unauthenticated callers.

## Check order

| API operation | Table check | Row check |
|---------------|-------------|-----------|
| create | `canCreate` | `canCreate` (with payload) |
| update/delete | `canUpdate`/`canDelete` | `canUpdate`/`canDelete` |
| view (single) | `canView` | `canView` |
| list/count | `canList` | `canView` on each returned row |

For `list`: every row must pass row-level `canView`. Design `canList` and
`canView` together, or filter via query to only return accessible rows.
""";

const cursorExtensionsMdc = r"""---
description: zonai extensions — lifecycle hooks, CreateExtension, UpdateExtension, DeleteExtension, AuthExtension, get/mutate/email globals
globs: lib/src/extensions/**
alwaysApply: false
---

# Zonai Extensions

Extensions are lifecycle hooks that run around database mutations and auth
events. They run between authorization and persistence.

## Execution order

```
rules → rate limits → beforeCreate → SQL insert → afterCreateSuccess
                                            ↓ (on failure)
                                      afterCreateError
```

## Base class and mixins

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../schemas/items.dart';

class ItemExtensions extends Extension<Item>
    with CreateExtension, UpdateExtension, DeleteExtension {
  ItemExtensions() : super(items);

  // CreateExtension
  @override
  Future<void> beforeCreate(Item object, Jwt? jwt) async {}

  @override
  Future<void> afterCreateSuccess(Item object, Jwt? jwt) async {
    mutate.update.one(
      collection: 'items',
      updates: [Update.column('status', .literal(1))],
      where: Eq('id', object.id),
    );
  }

  @override
  Future<void> afterCreateError(Object error, Jwt? jwt) async {}

  // UpdateExtension
  @override
  Future<void> beforeUpdate(Item row, Jwt? jwt) async {}

  @override
  Future<void> afterUpdateSuccess(Item before, Item after, Jwt? jwt) async {}

  @override
  Future<void> afterUpdateError(Object error, Jwt? jwt) async {}

  // DeleteExtension
  @override
  Future<void> beforeDelete(Item row, Jwt? jwt) async {}

  @override
  Future<void> afterDeleteSuccess(Item row, Jwt? jwt) async {}

  @override
  Future<void> afterDeleteError(Object error, Jwt? jwt) async {}
}

ItemExtensions main() => ItemExtensions();
```

Throwing from a **before** hook aborts the request.
Throwing from an **after** hook fails after the DB change committed.

## Auth extension (`AuthExtension` mixin)

```dart
class UserExtensions extends Extension<User> with AuthExtension {
  UserExtensions() : super(users);

  @override
  Future<void> onSignUp(User user, Jwt? jwt) async {
    email.send.verifyEmail(collection: 'users');
  }

  @override
  Future<void> onSignIn(User user, Jwt? jwt) async {}

  @override
  Future<void> onRefresh(User user, Jwt? jwt) async {}

  @override
  Future<void> onLogout(User user, Jwt? jwt) async {}
}

UserExtensions main() => UserExtensions();
```

## Side effect globals

| Global | Purpose |
|--------|---------|
| `get.one(collection:, where:)` | Read a single row (respects rules) |
| `get.many(collection:, where:)` | Read multiple rows |
| `mutate.create.one(collection:, values:)` | Queue a create side effect |
| `mutate.update.one(collection:, updates:, where:)` | Queue an update |
| `mutate.delete.many(tableName:, updates:, where:)` | Queue bulk deletes |
| `email.send.verifyEmail(collection:)` | Send verify-email link |
| `email.send.loginNotice(collection:)` | Send login notification |
| `email.send.passwordReset(collection:)` | Send password reset link |
| `email.send.magicLink(collection:)` | Send magic-link sign-in |
| `logger.debug/info/warn/error(msg)` | Log to server console |

`mutate` writes are **queued**, run after the main mutation commits, going
through rules+extensions again (up to 10 chained iterations).

The `extensionsPath` directory must exist and contain at least one `.dart` file
for the worker to compile.
""";

const cursorRateLimitsMdc = r"""---
description: zonai rate limits — TableRateLimits, AuthTableRateLimits, RateLimitPolicy, policy override methods
globs: lib/src/rate_limit/**
alwaysApply: false
---

# Zonai Rate Limits

Rate limiting is **optional**. Default: 100 requests per minute per IP per
collection+operation. Return `null` from any method to disable limiting for
that operation.

## Regular collection

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../schemas/items.dart';

final class ItemRateLimits extends TableRateLimits<ItemTable, Item> {
  ItemRateLimits() : super(items);

  @override
  Future<RateLimitPolicy?> getPolicy() async =>
      const RateLimitPolicy(maxRequests: 100, window: Duration(minutes: 1));

  @override
  Future<RateLimitPolicy?> limitPolicy() async =>
      const RateLimitPolicy(maxRequests: 50, window: Duration(minutes: 1));

  @override
  Future<RateLimitPolicy?> createPolicy() async => null; // unlimited
}

ItemRateLimits main() => ItemRateLimits();
```

Data policy methods (all default to 100 req/min):

| Method | Operation | HTTP |
|--------|-----------|------|
| `getPolicy()` | `view` | `GET /db` |
| `limitPolicy()` | `list` | `GET /db/list` |
| `countPolicy()` | `count` | `GET /db/count` |
| `createPolicy()` | `create` | `POST /db` |
| `updatePolicy()` | `update` | `PATCH /db` |
| `deletePolicy()` | `delete` | `DELETE /db` |

## Auth collection

```dart
final class UserRateLimits extends AuthTableRateLimits<UserTable, User> {
  UserRateLimits() : super(users);

  @override
  Future<RateLimitPolicy?> signInPolicy() async =>
      const RateLimitPolicy(maxRequests: 10, window: Duration(minutes: 15));

  @override
  Future<RateLimitPolicy?> signUpPolicy() async =>
      const RateLimitPolicy(maxRequests: 5, window: Duration(hours: 1));
}

UserRateLimits main() => UserRateLimits();
```

Auth policy methods: `signInPolicy`, `signUpPolicy`, `refreshTokenPolicy`,
`sendResetPasswordPolicy`, `sendVerifyEmailPolicy`, `sendOtpPolicy`,
`sendMagicLinkPolicy`, `confirmPolicy`, `logoutPolicy`, `logoutAllPolicy`,
`adminAuthenticatePolicy`, `adminSignInPolicy`.

## RateLimitPolicy

```dart
const RateLimitPolicy(
  maxRequests: 10,               // requests allowed per window
  window: Duration(minutes: 15), // sliding window duration
)
```

429 Too Many Requests is returned when the limit is exceeded.
""";

const cursorCronsMdc = r"""---
description: zonai crons — CronJob, Schedule.parse, run(), get/mutate/email globals, CronJwt
globs: lib/src/crons/**
alwaysApply: false
---

# Zonai Cron Jobs

Scheduled background tasks. Each file under `cronsPath` returns a `CronJob`
via `main()`. Jobs run inside the `db_crons` worker process.

## Basic cron job

```dart
import 'package:cron/cron.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class CleanupLogsJob extends CronJob {
  const CleanupLogsJob()
    : super(
        name: 'cleanup_logs',           // unique snake_case identifier
        schedule: Schedule.parse('0 3 * * *'), // daily at 03:00
      );

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    mutate.delete.many(
      tableName: 'logs',
      updates: [],
      where: Lt('created_at', cutoff),
    );
    logger.info('Queued log cleanup');
  }
}

CleanupLogsJob main() => const CleanupLogsJob();
```

## CronJob properties

| Property | Default | Purpose |
|----------|---------|---------|
| `name` | required | Unique snake_case job identifier (used in `_cron_jobs` history and on-demand invocation) |

## Running on demand

Jobs can be triggered by `name` outside their schedule:

- **Dev TUI:** `zonai dev`, press `j`, select job by name
- **HTTP API:** `POST /crons/run?name=<name>` with admin JWT (server must be running)
| `schedule` | required | When to run: `Schedule.parse('* * * * *')` |
| `strict` | `true` | `true` = skip missed runs; `false` = catch up on startup |
| `runOnStartup` | `false` | Run once immediately when crons start |

## Schedule examples

```dart
Schedule.parse('*/15 * * * *')  // every 15 minutes
Schedule.parse('0 3 * * *')      // daily at 03:00
Schedule.parse('0 0 * * 1')      // every Monday at midnight
```

Five-field cron: `minute hour day-of-month month day-of-week`.

## Side effect globals

Cron jobs access the same globals as extensions:

| Global | Purpose |
|--------|---------|
| `get.one(collection:, where:)` | Read a single row |
| `get.many(collection:, where:)` | Read multiple rows |
| `mutate.create.one(collection:, values:)` | Queue a create |
| `mutate.update.one(collection:, updates:, where:)` | Queue an update |
| `mutate.delete.many(tableName:, updates:, where:)` | Queue bulk deletes |
| `email.send.*` | Send transactional email |
| `logger.debug/info/warn/error(msg)` | Log to server console |

Cron jobs run as `CronJwt` — an internal admin-level identity. Rules applied
to `mutate` calls evaluate against this identity.

`mutate` writes are queued during `run()` and committed when the job finishes.
Each queued mutation goes through rules, operations, and extensions normally.

## Catch-up example

```dart
final class PurgeExpiredJwtsJob extends CronJob {
  const PurgeExpiredJwtsJob()
    : super(
        name: 'purge_expired_jwts',
        schedule: Schedule.parse('0 4 * * *'),
        strict: false,  // catch up if server was down
      );

  @override
  Future<void> run() async {
    mutate.delete.many(
      tableName: 'jwts',
      updates: [],
      where: Lt('expires_at', DateTime.now()),
    );
  }
}

PurgeExpiredJwtsJob main() => const PurgeExpiredJwtsJob();
```
""";

const cursorMdcFiles = <String, String>{
  'zonai-overview.mdc': cursorOverviewMdc,
  'zonai-schemas.mdc': cursorSchemasMdc,
  'zonai-operations.mdc': cursorOperationsMdc,
  'zonai-rules.mdc': cursorRulesMdc,
  'zonai-extensions.mdc': cursorExtensionsMdc,
  'zonai-rate-limits.mdc': cursorRateLimitsMdc,
  'zonai-crons.mdc': cursorCronsMdc,
};
