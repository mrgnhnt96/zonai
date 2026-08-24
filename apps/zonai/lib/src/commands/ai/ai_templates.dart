/// Template strings for AI coding assistant reference files.
library;

// ---------------------------------------------------------------------------
// Shared master reference document (used by Claude, Copilot, Windsurf, Cline)
// ---------------------------------------------------------------------------

const _doc = r"""
# Zonai Framework Reference

Zonai is a Dart CLI framework that compiles your declarative Dart code into a
project-linked server binary (plus optional worker executables) and runs a
SQLite-backed REST API. You write schemas, rules, operations, extensions, rate
limits, and crons — Zonai generates the SQL and handles HTTP.

**Runtime model**: `zonai serve` / `zonai build` produce a **project binary**
that links your ops and rules **in-process** (no IPC on the create/list hot
path). `zonai compile` also builds worker executables (`db_operations`,
`db_rules`, `db_extensions`, `db_rate_limit`, `db_crons`, `db_config`) under
`.zonai/executables/` for config/extensions/rate-limits/crons, ping/compat, and
the `ZONAI_FORCE_WORKERS=1` escape hatch. In dev, workers auto-recompile on file
changes; ops/rules edits require restarting `serve` so the linked entry reloads.

**Live queries**: every table has `GET /db/stream`, `/db/stream/list`, and
`/db/stream/count`. Prefer `zonai_client`'s `client.db.listen` over polling or
hand-rolled HTTP. Search for **stream** / **listen** — not "realtime", "SSE",
or "WebSocket". Streams reuse `canView` / `canList` / `canCount` rules.

**Runtime env (optional):** `ZONAI_FORCE_WORKERS`, `ZONAI_WORKER_TRANSPORT`
(`auto`|`process`|`isolate`), `ZONAI_WORKER_POOL_SIZE` (default 1),
`ZONAI_HTTP_WORKERS` (keep 1 — `>1` regresses list vs one SQLite file).
Worker IPC uses framed MessagePack; list/create also benefit from host caches,
batch row-rules, `requiresPerRowCheck => false` skip, skip-empty extensions,
and write-queue 503 backpressure.

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
  final ColumnType<String?> description;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
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
| `$.deviceToken(name, getter)` | `ColumnType<String?>` | Push recipient token; MUST be nullable |
| `$.dateTime(name, getter)` | `DateTimeColumn` | Client-settable timestamp |
| `$.createdAt(name, getter)` | `DateTimeColumn` | Auto-set on insert |
| `$.updatedAt(name, getter)` | `DateTimeColumn?` | Auto-set on update |
| `$.updatedWhen(name, getter, watchColumn:)` | `DateTimeColumn` | Auto-set when `watchColumn` changes |
| `$.isVerified(name, getter)` | `IsVerifiedColumn` | Auth tables |
| `$.enumerator(name, values, getter)` | `EnumColumn<E>` | Dart enum stored as TEXT |
| `$.enumList(name, values, getter)` | `EnumListColumn<E>` | List of enum values |
| `$.list(name, getter, fromJson:)` | `ListColumn<T>` | JSON array in TEXT |
| `$.map(name, getter)` | `MapColumn` | JSON object in TEXT |
| `$.photos(name, getter)` | `PhotosColumn` | List of `PhotoId` |
| `$.serverGenerated(name, getter)` | `ColumnType<String>` | Value client can never set; `safeCreate` fills `''` for rules; unlike `password`, not stripped from responses |

Nullable getter type (`String?`) → nullable SQL column.

Every `DateTimeColumn` (`dateTime`, `createdAt`, `updatedAt`, `updatedWhen`)
speaks epoch milliseconds on the wire in both directions — reads always come
back as an `int`, and writes accept either epoch milliseconds or an ISO-8601
string.

### Auth tables

```dart in:schema-file
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
  final ColumnType<DateTime?> updatedAt;
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
  @override
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

### Default HTTP surface (every table)

| Op | Method | Path |
|----|--------|------|
| get | GET | `/db` |
| list | GET | `/db/list` |
| count | GET | `/db/count` |
| stream-one | GET | `/db/stream` |
| stream-list | GET | `/db/stream/list` |
| stream-count | GET | `/db/stream/count` |
| create / create many | POST | `/db` / `/db/many` |
| update / update many | PATCH | `/db` / `/db/many` |
| delete / delete many | DELETE | `/db` / `/db/many` |

Table name is always in the JSON body (`?body=` for GET), never in the path.
Payload types: `StreamBody`, `StreamListBody`, `StreamCountBody` in
`zonai_schema`. Dart apps should use `package:zonai_client` —
`client.db.listen.one|list|count` — not a custom poller.

Prefer the typed client generated by `zonai gen client`
(`client.posts.list(...)` → `PostsRow`) over `client.db.list` with a table-name
string and a hand-written `fromJson`. It is an extension on the same client, so
both styles are valid in one file. Reads, writes and live queries are all
covered: `client.posts.listen.list(...)` is the typed mirror of
`client.db.listen.list`.

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

```dart in:project-file
class ItemRowRules extends RowRules<ItemTable, Item> {
  ItemRowRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt, Item row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Item before, Item after) async {
    if (jwt?.admin.canEdit == true) return true;
    return jwt?.userId.value == before.ownerId.value;
  }

  @override Future<bool> canCreate(Jwt? jwt, Item row) async => jwt != null;
  @override Future<bool> canDelete(Jwt? jwt, Item row) async =>
      jwt?.admin.canEdit == true;
}

ItemRowRules main() => ItemRowRules();
```

### Auth rules

`user_table_rules.dart`:

```dart in:project-file
final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);
  // canAuthenticate(Jwt? jwt, AuthType type) — default: true
}

UserTableRules main() => UserTableRules();
```

`user_row_rules.dart`:

```dart in:project-file
final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);
  // canSignUp(Jwt? jwt, AuthType type), canSignIn(...), canPasswordReset(...)
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

## Views

Read-only, query-defined collections — no backing SQLite table, no
`CREATE VIEW`, no migration. Built entirely on the existing schema/operations/
rules mechanism, using Raindrop's own join/select API.

**The schema lives in the operations file, never under `schemasPath`.**
raindrop_cli's migration generator finds *any* top-level variable typed as a
raindrop `Schema` inside `schemasPath` — regardless of what function produced
it — so a separate "views" folder next to `schemas/` would only avoid
migration generation by convention, not by construction. `operationsPath` is
never scanned for migrations, so defining the schema there is safe
structurally. Import only `zonai_schema` — it re-exports raindrop's query
builder (`.select`/`.from`/`.join`, `count`, etc.) already, so a separate
`package:raindrop/raindrop.dart` import isn't needed and will collide: both
packages would then export symbols like `Table`/`table`, producing
`ambiguous_import`.

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../ids.dart';
import '../schemas/authors.dart';
import '../schemas/posts.dart';

ViewOperations<PostSummary> main() =>
    ViewOperations(postSummary, PostSummaryQuery());

final class PostSummary {
  const PostSummary({
    required this.id,
    required this.title,
    required this.authorName,
  });

  final PostsId id;
  final String title;
  final String authorName;
}

final class PostSummaryTable extends Table<PostSummary> {
  PostSummaryTable(super.$)
    : id = $.id('id', (s) => s.id,
          fromString: PostsId.new, generate: PostsId.generate),
      title = $.text('title', (s) => s.title),
      authorName = $.text('author_name', (s) => s.authorName);

  @override
  PostSummary fromRow(RowReader read) => PostSummary(
    id: read(id), title: read(title)!, authorName: read(authorName)!,
  );

  final IdColumn<PostsId> id;
  final TextColumn title;
  final TextColumn authorName;
}

final postSummary = table('post_summary', PostSummaryTable.new);

final class PostSummaryQuery extends ViewQuery<PostSummary> {
  @override
  SelectFromBuilder<dynamic, dynamic, dynamic> query() => db
      .select(
        posts.id.aliasedAs('id'),
        posts.title.aliasedAs('title'),
        authors.name.aliasedAs('author_name'),
      )
      .from(posts)
      .join(authors, on: posts.authorId.equals(authors.id));

  @override
  SelectFromBuilder<dynamic, dynamic, dynamic> countQuery() => db
      .select(count(posts.id))
      .from(posts)
      .join(authors, on: posts.authorId.equals(authors.id));
}
```

`ViewQuery<R>` — implement `query()`/`countQuery()` with columns/joins only,
no `where`/`limit`/`offset`/`orderBy` (`ViewOperations` applies those
generically on top). Every selected column must use `.aliasedAs(name)`
matching the schema's column name exactly — Raindrop auto-aliases joined
columns as `"table__column"` otherwise, and row reconstruction breaks.

Rules use `ViewTableRules`/`ViewRowRules` (extend the regular `TableRules`/
`RowRules`), importing the schema from the operations file that declares
it — `canCreate`/`canUpdate`/`canDelete` are hard-denied, even for admin
tokens; only `canView`/`canList` (and row `canView`) are yours to override:

```dart
import 'package:zonai_schema/zonai_schema.dart';

import '../operations/post_summary_operations.dart';

final class PostSummaryTableRules
    extends ViewTableRules<PostSummaryTable, PostSummary> {
  PostSummaryTableRules() : super(postSummary);

  @override Future<bool> canView(Jwt? jwt) async => true;
  @override Future<bool> canList(Jwt? jwt) async => true;
}
PostSummaryTableRules main() => PostSummaryTableRules();
```

`ViewOperations` is `final` — construct it, don't extend it. The schema,
`ViewQuery`'s two methods, and the two rules files are the only things you
write; pagination, filtering, sort, and write rejection are handled
centrally, the same way for every view.

**Filtering caveat**: a caller's `where`/`orderBy` reference columns by the
alias `query()` selects them as. `WHERE` generally can't reference a
`SELECT` alias in SQL (unlike `ORDER BY`) — expose a column under its
natural, unambiguous source-table name if you need it filterable.

---

## Extensions

Lifecycle hooks around mutations and auth events.

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../schemas/items.dart';

class ItemExtensions extends Extension<Item> {
  ItemExtensions() : super(items);

  @override
  Future<void> beforeCreate(Item object, Jwt? jwt) async {
    logger.debug('Creating ${object.id}');
  }

  @override
  Future<void> afterCreateSuccess(Item object, Jwt? jwt) async {
    mutate.update.one(
      table: 'items',
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

Create, update and delete hooks are methods on `Extension<R>` itself, each
defaulting to a no-op -- override what you need, there is no mixin to add.

`AuthExtension<R>` is the only mixin, for auth tables:
`class UserExtensions extends Extension<User> with AuthExtension<User>`. Its
hooks are `onSignUp(R user, Jwt? jwt)`, `onSignIn`, `onRefresh`, `onLogout`,
`onPasswordReset` and `onExternalAuthFirstSeen(Map<String, Object?> claims)`.

### Side effect globals (from `package:zonai_schema/zonai_schema.dart`)

| Global | Purpose |
|--------|---------|
| `get.one(tableName:, where:)` | Read a single row |
| `get.many(tableName:, where:)` | Read multiple rows |
| `mutate.create.one(tableName:, object:)` | Queue a create |
| `mutate.update.one(table:, updates:, where:)` | Queue an update |
| `mutate.delete.many(tableName:, where:)` | Queue deletes |
| `email.send.verifyEmail(...)` | Send verify-email link |
| `email.send.loginNotice(...)` | Send login notification |
| `push(message, table:, column:, where:)` | Queue a push fan-out; returns a `PushJobId` |
| `logger.debug/info/warn/error(msg)` | Log to server console |

Writes via `mutate` are queued and committed after the main mutation, going
through rules+extensions again (up to 10 chained iterations).

`push` behaves differently from the queued writes above: it is awaited and
returns the id of a durably recorded job, not a delivery receipt, and the
fan-out outlives the request. Call it from `after*` hooks only — a `before`
hook runs before the write, and a notification announcing something that may
not happen cannot be recalled. Recipients are named by a query over a
`$.deviceToken` column, never a list of tokens. Requires `AppConfig.push`;
without it the call throws. See https://docs.zonai.dev/push/overview

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
  CleanupLogsJob()
    : super(
        name: 'cleanup_logs',           // unique snake_case identifier
        schedule: Schedule.parse('0 3 * * *'), // daily at 03:00
      );

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    mutate.delete.many(
      tableName: 'logs',
      where: Lt('created_at', cutoff),
    );
    logger.info('Queued log cleanup older than $cutoff');
  }
}

CleanupLogsJob main() => CleanupLogsJob();
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
    appName: 'My App',
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

`String.fromEnvironment(...)` values above are populated at **compile time**
from `.env`/`.env.<flavor>` files and `--dart-define KEY=VALUE` flags passed
to `zonai compile`/`zonai build` — see **Release & deployment** below. The
`.env` file is found automatically; there is no `--dart-define-from-file`
flag to point at it. This is a separate mechanism from `buildSettings` in
`zonai.yaml` (target
OS/arch only, for cross-compiling); `buildSettings` having no env/secret
fields does not mean there's no way to inject secrets.

---

## CLI Commands

```
dart run zonai build       # project-linked binary + workers + deploy bundle
dart run zonai serve       # start HTTP server (JIT project entry; watchers)
dart run zonai dev         # interactive TUI (compile, serve, logs, schema scaffold)
dart run zonai compile     # compile worker executables only
dart run zonai db migrate  # run SQL migrations
dart run zonai db admin    # manage admin accounts
dart run zonai gen client  # generate a typed Dart client from the schema
dart run zonai rules       # inspect compiled authorization rules
dart run zonai ping        # test worker executables
dart run zonai version     # show version + check for updates
dart run zonai ai update   # refresh these reference files after an upgrade
```

`zonai gen client` writes a typed client — `client.posts.list(...)` returning a
`PostsRow` — into a directory the **app** owns, configured by a `client:` block
in `zonai.yaml` (`output` is required and has no default, because the server
project cannot be an app dependency). It covers reads (`get`/`list`/`count`),
writes (`create`/`createMany`/`update`/`updateMany`/`delete`/`deleteMany`) and
live queries (`client.posts.listen.one|list|count`).

Filters and ordering go through column tokens: `Posts.title.eq('x')`,
`Posts.createdAt.desc`, `Posts.body.isNull` — the operators a column offers
depend on its type, and a secret column has no token at all. `expand` takes
typed paths (`Posts.expand.authorId.companyId`). Update fields take a `Patch`,
so `Field.set(v)` and `Field.clear()` are different operations — the second
sets NULL, which a nullable argument cannot express.

An enum column gets its own generated type: an extension type over `String`
with named constants (`BooksShelf.reading`, plus `values` and `isKnown`), not a
Dart `enum` — a member the server adds later must not become a parse failure in
a client that shipped before it existed. Comparisons still work
(`row.shelf == BooksShelf.reading`); reach for `.value` where a raw `String` is
wanted, because to the analyzer the type is not one.

One import is enough. The generated barrel re-exports `zonai_client`, so
`Where`, `Paginated`, `OrderByTerm` and the rest are in scope from the
generated `zonai_client.g.dart` alone. When a table name collides with
something `zonai_client` exports — a `photos` table against its `Photos` — the
barrel hides the package's version and says so in the file; the name you get is
your own.

A view generates no write surface. Tables whose names start with `_` are
zonai's own and are skipped unless named in `client.tables.include`. Re-run it
after a schema change; `--check` fails when the committed output is stale.

---

## Release & deployment

`zonai compile` builds workers in place under `.zonai/executables/`.
`zonai build` does that plus copies migrations, `zonai.yaml`, and compiles a
**project-linked** `build/zonai` that embeds your ops/rules and the full CLI
(`serve`, `db`, …) — a self-contained bundle ready to ship. Both accept
`--release` (strip `assert(...)` from compiled code, disable dev-only file
watchers/keyboard shortcuts), `--flavor <name>` (select `.env.<name>`), and
repeated `--dart-define KEY=VALUE` flags (override/add compile-time env
values on top of the selected `.env` file — CLI wins on key collisions; use
space-separated form, not `--dart-define=KEY=VALUE`, since a joined value
containing its own `=` won't parse).

There is **no `--dart-define-from-file`** flag and none is needed: `.env` /
`.env.<flavor>` is read from the working directory automatically, so the env
file never has to be named on the command line. It is `KEY=VALUE` lines, not
JSON. Zonai's parser ignores unknown flags silently, so
`zonai build --dart-define-from-file env.json` exits 0, warns about nothing
and injects **zero** defines — every `String.fromEnvironment` then falls back
to its default. To use a different file, name it `.env.<flavor>` and pass
`--flavor <flavor>`.

Cross-compile via `buildSettings` in `zonai.yaml` (unrelated to secrets/env
values above — this only picks target OS/arch, it has no define/env field):

```yaml
buildSettings:
  targetOs: linux   # linux | macos | windows
  targetArch: x64   # x64 | arm64
```

Defaults to the machine running `build`. The project binary and workers are
compiled with `dart compile exe` (including `--target-os` / `--target-arch`
when set), so the normal Dart AOT rule applies: you cannot compile a macOS or
Windows target from a different host OS.

**No Docker or container runtime is needed to produce a Linux deploy bundle
from macOS (or any other host)** — `buildSettings` + `zonai build` cross-compile
natively via `dart compile exe`. A container is only relevant if you're
rebuilding the zonai CLI framework itself from source (e.g. an unreleased
framework fix); that is a different, much narrower task than shipping your
app, and does not apply to a normal deploy.

Day-to-day `serve` / `db` from a project root re-exec into the generated
project entry (`.dart_tool/zonai/project_main.dart` under JIT, or
`.zonai/zonai` with `--release`) so ops/rules stay in-process. Set
`ZONAI_FORCE_WORKERS=1` to keep Mailman IPC for ops/rules instead.

---

## Generated workers

`zonai compile` / `zonai build` still produce executables in
`.zonai/executables/` (or `build/.zonai/executables/`):
- `db_operations.exe` — SQL generation (also linked into the project binary)
- `db_rules.exe` — authorization (also linked into the project binary)
- `db_extensions.exe` — lifecycle hooks
- `db_rate_limit.exe` — rate limiting
- `db_crons.exe` — scheduled jobs
- `db_config.exe` — app config

Intermediate Dart sources (including `project_main.dart`) are written to
`.dart_tool/zonai/` before compilation.
""";

// ---------------------------------------------------------------------------
// Single-file tool templates
// ---------------------------------------------------------------------------

const claudeMd =
    r"""# Zonai Project

This is a **zonai** application. Zonai compiles your Dart code into a
project-linked server binary (ops/rules in-process) plus worker executables
for config, extensions, rate limits, and crons.

Use `dart run zonai dev` to launch the interactive TUI, or
`dart run zonai serve` to start the server (project entry + auto-recompile).

""" +
    _doc;

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

Zonai is a Dart CLI framework that compiles declarative Dart code into a
project-linked server binary and optional worker executables, and runs a
SQLite-backed REST API server.

**Live queries**: `GET /db/stream`, `/db/stream/list`, `/db/stream/count` push
updates when data changes. Prefer `zonai_client` (`client.db.listen`) over
polling or hand-rolled HTTP. Search for **stream** / **listen**, not
"realtime"/"SSE"/"WebSocket".

**Runtime model**: `zonai serve` / `zonai build` link your ops and rules
**in-process** into the project binary (or JIT `project_main` in dev).
`zonai compile` also builds workers from your source:
- `db_operations` — custom CRUD SQL (`lib/src/operations/`) — also linked in-process
- `db_rules` — authorization (`lib/src/rules/`) — also linked in-process
- `db_extensions` — lifecycle hooks (`lib/src/extensions/`)
- `db_rate_limit` — rate limiting (`lib/src/rate_limit/`)
- `db_crons` — scheduled jobs (`lib/src/crons/`)
- `db_config` — app config (`lib/src/config/`)

Extensions/config/rate-limits/crons still run as worker processes. Ops/rules
use Mailman workers only with `ZONAI_FORCE_WORKERS=1`. Worker binaries
auto-recompile on file changes during `zonai serve`; restart serve after
ops/rules edits so the linked entry reloads.

**Runtime env (optional):** `ZONAI_FORCE_WORKERS`, `ZONAI_WORKER_TRANSPORT`
(`auto`|`process`|`isolate`), `ZONAI_WORKER_POOL_SIZE` (default 1),
`ZONAI_HTTP_WORKERS` (keep 1). IPC is framed MessagePack; host caches,
batch row-rules, `requiresPerRowCheck => false`, skip-empty extensions, and
write-queue 503 apply on the hot path.

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
dart run zonai build       # project-linked binary + workers + deploy bundle
dart run zonai serve       # start server (JIT project entry; watchers)
dart run zonai dev         # interactive TUI
dart run zonai compile     # compile worker executables only
dart run zonai db migrate  # run SQL migrations
dart run zonai gen client  # generate a typed Dart client from the schema
dart run zonai rules       # inspect compiled authorization rules
dart run zonai ping        # test worker executables
dart run zonai version     # show version
dart run zonai ai update   # refresh these reference files after an upgrade
```

`zonai gen client` needs a `client:` block in `zonai.yaml` naming an `output`
directory the app owns; there is no default. It generates reads, writes and
live queries — `get`/`list`/`count`, the six mutations, and
`client.posts.listen.*` — with column tokens for filters (`Posts.title.eq('x')`)
and typed `expand` paths. An enum column becomes an extension type over
`String`, with `.value` for the raw one. The generated barrel re-exports
`zonai_client`, so one import names the whole query vocabulary. It skips
`_`-prefixed system tables unless `client.tables.include` names them.

## Config (`lib/src/config/`)

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
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

`String.fromEnvironment(...)` values above are populated at **compile time**
from `.env`/`.env.<flavor>` files and `--dart-define KEY=VALUE` flags passed
to `zonai compile`/`zonai build` — see `zonai-release.mdc`. The `.env` file is
found automatically; there is no `--dart-define-from-file` flag to point at
it. This is separate from `buildSettings` above (target OS/arch only, for
cross-compiling); `buildSettings` having no env/secret fields does not mean
there's no way to inject secrets.
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
  final ColumnType<String?> description;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final items = table('items', ItemTable.new);
```

## Auth table

```dart no-analyze
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
| `$.deviceToken(name, getter)` | `ColumnType<String?>` | Push recipient token; MUST be nullable |
| `$.dateTime(name, getter)` | `DateTimeColumn` | Client-settable timestamp |
| `$.createdAt(name, getter)` | `DateTimeColumn` | Auto-set on insert |
| `$.updatedAt(name, getter)` | `DateTimeColumn?` | Auto-set on update |
| `$.updatedWhen(name, getter, watchColumn:)` | `DateTimeColumn` | Auto-set when `watchColumn` changes |
| `$.isVerified(name, getter)` | `IsVerifiedColumn` | Auth tables |
| `$.enumerator(name, values, getter)` | `EnumColumn<E>` | Dart enum stored as TEXT |
| `$.enumList(name, values, getter)` | `EnumListColumn<E>` | List of enum values |
| `$.list(name, getter, fromJson:)` | `ListColumn<T>` | JSON array in TEXT |
| `$.map(name, getter)` | `MapColumn` | JSON object in TEXT |
| `$.photos(name, getter)` | `PhotosColumn` | List of `PhotoId` |
| `$.serverGenerated(name, getter)` | `ColumnType<String>` | Value client can never set; `safeCreate` fills `''` for rules; unlike `password`, not stripped from responses |

Nullable getter (`String?`) → nullable column in SQL.

Every `DateTimeColumn` (`dateTime`, `createdAt`, `updatedAt`, `updatedWhen`)
speaks epoch milliseconds on the wire in both directions — reads always come
back as an `int`, and writes accept either epoch milliseconds or an ISO-8601
string.

## ID classes (`lib/src/ids.dart`)

```dart
import 'package:zonai_schema/zonai_schema.dart' as z;

class ItemsId implements z.Id {
  const ItemsId(this.value);
  factory ItemsId.generate() => ItemsId(z.Id.generate('it'));
  @override
  final String value;
  @override String toString() => value;
  @override bool operator ==(Object o) => o is ItemsId && o.value == value;
  @override int get hashCode => value.hashCode;
}
```

Use a unique 2-3 char suffix per table. IDs are `<timestamp>_<suffix>`.

For a read-only, query-defined collection (a join/projection with no backing
table), see `zonai-views.mdc` instead of declaring it here.
""";

const cursorOperationsMdc = r"""---
description: zonai operations — TableOperations, AuthOperations, custom CRUD SQL, JWT claims
globs: lib/src/operations/**
alwaysApply: false
---

# Zonai Operations

Operations are **optional** — default CRUD SQL is auto-generated for every
table (get/list/count/**stream**/create/update/delete). Add a file under
`operationsPath` only to:
- Override SQL for specific operations
- Add custom JWT claims on auth collections

**Live queries** (no polling): `GET /db/stream`, `/db/stream/list`,
`/db/stream/count` — use `zonai_client` `client.db.listen`. Search for
**stream**, not "realtime"/"SSE". With a typed client from `zonai gen client`,
prefer its mirror: `client.posts.listen.one|list|count`, which yields decoded
rows. Note `listen.list` yields `List<PostsRow>`, not a `Paginated` — the
streaming endpoint carries no page metadata.

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

```dart no-analyze
@override
rd.ToQuery<PostTable, Post> custom(
  String operation, {
  Where? where,
  List<Update> updates = const [],
}) {
  return switch (operation) {
    'archive' => db
        .update(posts)
        .setAll([UpdateableColumn(table['archived'], true)])
        .where(RawSqlFilter(where!.sql(table.name)))
        .toQuery(),
    _ => super.custom(operation, where: where, updates: updates),
  };
}
```

Custom operations still need matching entries in `TableRules.customOperations`/
`RowRules.customOperations` (keyed by the same operation name) or they're
denied — see `zonai-rules.mdc`.

One file per collection. `main()` must return a non-null `TableOperations`.

For a read-only view's operations file (`ViewOperations`/`ViewQuery` instead
of default CRUD), see `zonai-views.mdc`.
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

```dart in:project-file
class ItemRowRules extends RowRules<ItemTable, Item> {
  ItemRowRules() : super(items);

  @override
  Future<bool> canView(Jwt? jwt, Item row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Item before, Item after) async {
    if (jwt?.admin.canEdit == true) return true;
    return jwt?.userId.value == before.ownerId.value;
  }

  @override Future<bool> canCreate(Jwt? jwt, Item row) async => jwt != null;
  @override Future<bool> canDelete(Jwt? jwt, Item row) async =>
      jwt?.admin.canEdit == true;
}

ItemRowRules main() => ItemRowRules();
```

## Auth collection rules

`user_table_rules.dart`:

```dart in:project-file
final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);
  // canAuthenticate(Jwt? jwt, AuthType type) → bool — default: true
}

UserTableRules main() => UserTableRules();
```

`user_row_rules.dart` — row CRUD defaults let a user view and modify their own
row, with elevated access for admins:

```dart in:project-file
final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);
  // canSignUp(Jwt? jwt, AuthType type), canSignIn(...), canPasswordReset(...)
}

UserRowRules main() => UserRowRules();
```

## Custom operations

`TableOperations.custom(operation, ...)` calls need a matching entry, keyed by
the same operation name, on both table and row rules — otherwise they're denied:

```dart in:table-rules
@override
Map<String, CustomTableOperationRule> get customOperations => {
  'archive': (jwt) async => jwt?.admin.canEdit == true,
};
```

```dart in:row-rules-item
@override
Map<String, CustomRowOperationRule<Item>> get customOperations => {
  'archive': (jwt, before, after) async => jwt?.admin.canEdit == true,
};
```

The row rule receives `before`/`after` exactly like `canUpdate` — the `Update`s
passed to `custom()` are simulated the same way ahead of the write.

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

For a read-only view's rules (`ViewTableRules`/`ViewRowRules`, which hard-deny
create/update/delete), see `zonai-views.mdc`.
""";

const cursorViewsMdc = r"""---
description: zonai views — read-only, query-defined collections (ViewQuery, ViewOperations, ViewTableRules, ViewRowRules)
globs: lib/src/operations/**
alwaysApply: false
---

# Zonai Views

A view is a read-only collection defined by a query instead of a real SQLite
table — typically a join or projection across other collections. Exposed
through the same `/db` surface as regular collections, and goes through the
same rules checks. No `CREATE VIEW`, no migration, no raindrop changes — a
view is one operations file (schema + query) plus rules files, wired
together like any other collection.

## Schema + query — both in the operations file, never under `schemasPath`

raindrop_cli's migration generator finds *any* top-level variable typed as a
raindrop `Schema` inside `schemasPath` — regardless of what function produced
it — so a separate "views" folder next to `schemas/` would only avoid
migration generation by convention, not by construction. `operationsPath` is
never scanned for migrations, so defining the schema there instead is safe
structurally.

Import only `zonai_schema` — it re-exports raindrop's query builder
(`.select`/`.from`/`.join`, `count`, etc.) already, so a separate
`package:raindrop/raindrop.dart` import isn't needed and will collide: both
packages would then export symbols like `Table`/`table`, producing
`ambiguous_import`.

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../ids.dart';
import '../schemas/authors.dart';
import '../schemas/posts.dart';

ViewOperations<PostSummary> main() =>
    ViewOperations(postSummary, PostSummaryQuery());

final class PostSummary {
  const PostSummary({
    required this.id,
    required this.title,
    required this.authorName,
  });

  final PostsId id;
  final String title;
  final String authorName;
}

final class PostSummaryTable extends Table<PostSummary> {
  PostSummaryTable(super.$)
    : id = $.id('id', (s) => s.id,
          fromString: PostsId.new, generate: PostsId.generate),
      title = $.text('title', (s) => s.title),
      authorName = $.text('author_name', (s) => s.authorName);

  @override
  PostSummary fromRow(RowReader read) => PostSummary(
    id: read(id), title: read(title)!, authorName: read(authorName)!,
  );

  final IdColumn<PostsId> id;
  final TextColumn title;
  final TextColumn authorName;
}

final postSummary = table('post_summary', PostSummaryTable.new);

final class PostSummaryQuery extends ViewQuery<PostSummary> {
  @override
  SelectFromBuilder<dynamic, dynamic, dynamic> query() => db
      .select(
        posts.id.aliasedAs('id'),
        posts.title.aliasedAs('title'),
        authors.name.aliasedAs('author_name'),
      )
      .from(posts)
      .join(authors, on: posts.authorId.equals(authors.id));

  @override
  SelectFromBuilder<dynamic, dynamic, dynamic> countQuery() => db
      .select(count(posts.id))
      .from(posts)
      .join(authors, on: posts.authorId.equals(authors.id));
}
```

The schema half is an ordinary `Table<R>` — `Table.safeCreate`/`fromRow`
reconstruct rows from raw SQL result maps exactly like a regular collection.

`ViewQuery<R>` — implement `query()`/`countQuery()` with columns/joins only,
never `where`/`limit`/`offset`/`orderBy` (`ViewOperations` applies those
generically on top, the same way default `list()` does for a regular table):

- **Alias every selected column with `.aliasedAs(name)`**, matching the
  schema's declared column name exactly. Raindrop auto-qualifies and
  auto-aliases every projected column as `"table__column"` the moment a query
  has a join — without `.aliasedAs`, the raw result won't have a column named
  `author_name` at all, and `Table.safeCreate` can't reconstruct a row.
- **`countQuery()` mirrors the same joins as `query()`**, projecting a
  countable expression (`count(...)`) instead of the column list.
- **Never call `.where`/`.limit`/`.offset`/`.orderBy` inside `query()`/
  `countQuery()`** — a view can't opt out of the generic pagination/filter
  layer `ViewOperations` applies for every request.

`ViewQuery` is `abstract base class` — subclass with `final class`.
`ViewOperations` is `final` — construct it, don't extend it; that's what
guarantees `list()`/`count()` can never be overridden to bypass the
where/limit/offset logic or the write rejection below.

## Rules — `ViewTableRules`/`ViewRowRules`

Extend the regular `TableRules`/`RowRules` base classes, but
`canCreate`/`canUpdate`/`canDelete` are hard-denied already — including for
admin tokens, which the regular base classes grant by default. Only
`canView`/`canList` (table) and `canView` (row) are yours to override. Import
the schema from the operations file that declares it:

```dart
import 'package:zonai_schema/zonai_schema.dart';

import '../operations/post_summary_operations.dart';

final class PostSummaryTableRules
    extends ViewTableRules<PostSummaryTable, PostSummary> {
  PostSummaryTableRules() : super(postSummary);

  @override Future<bool> canView(Jwt? jwt) async => true;
  @override Future<bool> canList(Jwt? jwt) async => true;
}
PostSummaryTableRules main() => PostSummaryTableRules();
```

```dart
import 'package:zonai_schema/zonai_schema.dart';

import '../operations/post_summary_operations.dart';

final class PostSummaryRowRules
    extends ViewRowRules<PostSummaryTable, PostSummary> {
  PostSummaryRowRules() : super(postSummary);

  @override
  Future<bool> canView(Jwt? jwt, PostSummary row) async => true;
}
PostSummaryRowRules main() => PostSummaryRowRules();
```

These go under `rulesPath` exactly like any other collection's rules files,
keyed by the view's table name.

## Filtering caveat

A caller's `where`/`orderBy` reference columns by the alias `query()` selects
them as. `ORDER BY` can reference a `.select` alias; `WHERE` generally cannot
in standard SQL, since it's evaluated before the `SELECT` list. Expose a
column under its natural, unambiguous source-table name if you need it
filterable — not a renamed alias that only makes sense in the projection.

This also affects the default sort when no `orderBy` is given: it falls back
to an unqualified `"column"` reference (no table prefix), since a view has no
real `FROM`/`JOIN` target to qualify with. If two joined tables share a
column name in the default-sort candidate list (commonly `id`), that
reference is ambiguous — pass an explicit `orderBy` (or `orderBy: []` to opt
out of the default) rather than relying on the fallback.

## Write access

Denied twice over: rules deny it before SQL is ever built, and
`ViewOperations` itself throws `UnsupportedError` from
`insert`/`insertMany`/`update`/`delete` if somehow reached anyway. In
practice, `POST`/`PATCH`/`DELETE` against a view return a plain `403` from
the rules layer.
""";

const cursorExtensionsMdc = r"""---
description: zonai extensions — lifecycle hooks, create/update/delete hooks, AuthExtension, get/mutate/email globals
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

## Base class and hooks

```dart
import 'package:zonai_schema/zonai_schema.dart';
import '../schemas/items.dart';

class ItemExtensions extends Extension<Item> {
  ItemExtensions() : super(items);

  // Create hooks
  @override
  Future<void> beforeCreate(Item object, Jwt? jwt) async {}

  @override
  Future<void> afterCreateSuccess(Item object, Jwt? jwt) async {
    mutate.update.one(
      table: 'items',
      updates: [Update.column('status', .literal(1))],
      where: Eq('id', object.id),
    );
  }

  @override
  Future<void> afterCreateError(Object error, Jwt? jwt) async {}

  // Update hooks
  @override
  Future<void> beforeUpdate(Item row, Jwt? jwt) async {}

  @override
  Future<void> afterUpdateSuccess(Item before, Item after, Jwt? jwt) async {}

  @override
  Future<void> afterUpdateError(Object error, Jwt? jwt) async {}

  // Delete hooks
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
`beforeSignUp` is the auth-side equivalent: throw `SignUpDeclinedException`
to answer the caller 403 with your own reason, before any row exists.

## Auth extension (`AuthExtension` mixin)

```dart in:project-file
class UserExtensions extends Extension<User> with AuthExtension<User> {
  UserExtensions() : super(users);

  // Runs BEFORE the row is inserted -- throw to refuse the sign-up (403 with
  // this reason, no row, no session, no verify email). Password, OTP and
  // magic-link only; OAuth first-seen declines via onExternalAuthFirstSeen.
  @override
  Future<void> beforeSignUp(SignUpCandidate candidate, Jwt? jwt) async {
    if (!candidate.email.endsWith('@acme.com')) {
      throw const SignUpDeclinedException('Sign-up is limited to Acme staff');
    }
  }

  @override
  Future<void> onSignUp(User user, Jwt? jwt) async {
    email.send.verifyEmail(
      EmailAddress(address: user.email),
      table: 'users',
    );
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
| `get.one(tableName:, where:)` | Read a single row (respects rules) |
| `get.many(tableName:, where:)` | Read multiple rows |
| `mutate.create.one(tableName:, object:)` | Queue a create side effect |
| `mutate.update.one(table:, updates:, where:)` | Queue an update |
| `mutate.delete.many(tableName:, where:)` | Queue bulk deletes |
| `email.send.verifyEmail(to, table:)` | Send verify-email link |
| `email.send.loginNotice(to, table:)` | Send login notification |
| `email.send.passwordReset(to, table:)` | Send password reset link |
| `email.send.magicLink(to, table:)` | Send magic-link sign-in |
| `push(message, table:, column:, where:)` | Queue a push fan-out; returns a `PushJobId` |
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
| `getPolicy()` | `view` | `GET /db`, `GET /db/stream` |
| `limitPolicy()` | `list` | `GET /db/list`, `GET /db/stream/list` |
| `countPolicy()` | `count` | `GET /db/count`, `GET /db/stream/count` |
| `createPolicy()` | `create` | `POST /db` |
| `updatePolicy()` | `update` | `PATCH /db` |
| `deletePolicy()` | `delete` | `DELETE /db` |

## Auth collection

```dart in:project-file
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

```dart in:expression
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
  CleanupLogsJob()
    : super(
        name: 'cleanup_logs',           // unique snake_case identifier
        schedule: Schedule.parse('0 3 * * *'), // daily at 03:00
      );

  @override
  Future<void> run() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    mutate.delete.many(
      tableName: 'logs',
      where: Lt('created_at', cutoff),
    );
    logger.info('Queued log cleanup');
  }
}

CleanupLogsJob main() => CleanupLogsJob();
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

```dart in:expression
Schedule.parse('*/15 * * * *'), // every 15 minutes
Schedule.parse('0 3 * * *'),    // daily at 03:00
Schedule.parse('0 0 * * 1'),    // every Monday at midnight
```

Five-field cron: `minute hour day-of-month month day-of-week`.

## Side effect globals

Cron jobs access the same globals as extensions:

| Global | Purpose |
|--------|---------|
| `get.one(tableName:, where:)` | Read a single row |
| `get.many(tableName:, where:)` | Read multiple rows |
| `mutate.create.one(tableName:, object:)` | Queue a create |
| `mutate.update.one(table:, updates:, where:)` | Queue an update |
| `mutate.delete.many(tableName:, where:)` | Queue bulk deletes |
| `email.send.*` | Send transactional email |
| `push(message, table:, column:, where:)` | Queue a push fan-out; returns a `PushJobId` |
| `logger.debug/info/warn/error(msg)` | Log to server console |

Cron jobs run as `CronJwt` — an internal admin-level identity. Rules applied
to `mutate` calls evaluate against this identity.

`mutate` writes are queued during `run()` and committed when the job finishes.
Each queued mutation goes through rules, operations, and extensions normally.

## Catch-up example

```dart in:project-file
final class PurgeExpiredJwtsJob extends CronJob {
  PurgeExpiredJwtsJob()
    : super(
        name: 'purge_expired_jwts',
        schedule: Schedule.parse('0 4 * * *'),
        strict: false,  // catch up if server was down
      );

  @override
  Future<void> run() async {
    mutate.delete.many(
      tableName: 'jwts',
      where: Lt('expires_at', DateTime.now()),
    );
  }
}

PurgeExpiredJwtsJob main() => PurgeExpiredJwtsJob();
```
""";

const cursorReleaseMdc = r"""---
description: zonai release & deployment — build vs compile, --release/--flavor/--dart-define (there is no --dart-define-from-file), cross-compiling via buildSettings
globs: zonai.yaml
alwaysApply: false
---

# Zonai Release & Deployment

## `build` vs `compile`

| | `compile` | `build` |
| --- | --- | --- |
| Worker output | `.zonai/executables/*.exe` | `build/.zonai/executables/*.exe` |
| Project binary | not built | `build/zonai` — **project-linked** (ops/rules + full CLI) |
| Migrations | not copied | SQL copied into `build/` |
| `zonai.yaml` | not copied | copied into `build/` |
| Typical use | local workers, quick rebuilds | CI, deploy hosts, containers |

```bash
dart run zonai build --release --flavor prod   # deploy bundle under build/
dart run zonai compile --release               # workers only, in place
```

`--release` strips `assert(...)` from compiled code and disables dev-only file
watchers/keyboard shortcuts during `serve`. `--flavor <name>` selects
`.env.<name>` for compile-time env defines. Repeated `--dart-define
KEY=VALUE` flags override/add values on top of that file (CLI wins on key
collisions) without editing it — use space-separated form, not
`--dart-define=KEY=VALUE`.

## No `--dart-define-from-file`

That flag does not exist in zonai, and nothing replaces it, because the env
file is never named on the command line: `.env` — or `.env.<flavor>` when
`--flavor` is passed — is read from the working directory on every compile and
turned into `-D` defines automatically.

| Reaching for | Do this instead |
| --- | --- |
| `--dart-define-from-file=env.json` | Nothing — put the keys in `.env` |
| A different file per environment | Name it `.env.<flavor>`, pass `--flavor <flavor>` |
| A file elsewhere on disk | Run the command from that directory, or copy it to `.env` there |
| One-off keys, no file | `--dart-define KEY=VALUE`, repeated |

Two traps:

- The file is **`KEY=VALUE` lines, not JSON** (`#` comments, quotes optional
  around values with spaces). A JSON file will not load.
- **Unknown flags are ignored, not rejected.** zonai's parser collects every
  `--flag value` pair and commands read only the keys they know, so
  `zonai build --dart-define-from-file env.json` exits 0, prints no warning
  and injects nothing — every `String.fromEnvironment` silently falls back to
  its `defaultValue` (`''` when there is none). Check the flag name first when
  a build is missing values.

## Cross-compiling

`buildSettings` is unrelated to secrets/env values above — it only picks
target OS/arch, and has no define/env field:

```yaml
# zonai.yaml
buildSettings:
  targetOs: linux   # linux | macos | windows
  targetArch: x64   # x64 | arm64
```

Defaults to the machine running `build`. The project binary and workers are
compiled with `dart compile exe` (plus `--target-os` / `--target-arch` when
set). You cannot compile a macOS or Windows target from a different host OS.

**No Docker/container runtime needed** to produce a Linux bundle from macOS —
this is a native cross-compile. Docker only enters the picture if you're
rebuilding the zonai CLI framework itself from source, which is unrelated to
shipping a normal app.

`build/zonai` is **not** a copy or download of the published CLI — it is
compiled from generated `.dart_tool/zonai/project_main.dart` with your
schemas/ops/rules linked in. Set `ZONAI_FORCE_WORKERS=1` to force Mailman
IPC for ops/rules even on a project binary.
""";

const cursorMdcFiles = <String, String>{
  'zonai-overview.mdc': cursorOverviewMdc,
  'zonai-schemas.mdc': cursorSchemasMdc,
  'zonai-operations.mdc': cursorOperationsMdc,
  'zonai-rules.mdc': cursorRulesMdc,
  'zonai-views.mdc': cursorViewsMdc,
  'zonai-extensions.mdc': cursorExtensionsMdc,
  'zonai-rate-limits.mdc': cursorRateLimitsMdc,
  'zonai-crons.mdc': cursorCronsMdc,
  'zonai-release.mdc': cursorReleaseMdc,
};
