# Typed client generation — design

Status: **investigation + plan**, nothing implemented. No branch yet.
Revision 3 — supersedes the first two passes; see §11 for what changed and why.

Today every database call from `zonai_client` is stringly typed: the table name is a
`String`, the filter columns are `String`s, the create payload is a
`Map<String, dynamic>`, and the response comes back as `Map<String, Object?>` unless
the caller writes a `fromJson` by hand. The server already holds a complete,
machine-readable description of every table. This document proposes generating a
per-project typed layer from it, and hanging that layer off the existing
`ZonaiClient` **as an extension**, so `zonai_client` itself ships unchanged.

Every `dart` fence below is tagged `no-analyze`: it describes an API that does not
exist yet. They become analyzable snippets in `apps/docs/content/dart-client/` when
the code lands (see `docs/doc-snippet-drift-fix-plan.md`).

---

## 1. What exists today (read before changing anything)

| Concern | Where |
| --- | --- |
| Generic client DB surface (`get<T>`, `list<T>`, … each taking a `fromJson`) | `libs/zonai_client/lib/src/db.dart` |
| Streaming surface (`one<T>`, `list<T>`, `count`) | `libs/zonai_client/lib/src/db_listen.dart` |
| Client entry point, public `db` field | `libs/zonai_client/lib/src/zonai_client.dart:114` |
| Route-level generated client (from revali) | `libs/zonai_client/lib/gen/` |
| Public barrel + its `show` list | `libs/zonai_client/lib/zonai_client.dart` |
| Barrel completeness test + recorded exclusions | `libs/zonai_client/test/export_surface_test.dart` |
| **Full per-table shape** (`name`, `kind`, `isNullable`, `isPrimaryKey`, `autoIncrement`, `sqlType`, `defaultValue`, `foreignKey`, `enumValues`, `isSecret`, `isReadOnly`) | `libs/zonai_schema/lib/src/types/schema_shape.dart` |
| Shape derived from a live table | `libs/zonai_schema/lib/src/schema_shape_from_table.dart:24` |
| **Every** table's shape, in one call | `libs/zonai_schema/lib/src/handlers/operations/db_operations.dart:211` (`_getAllTableSchemaShapes`, over `operationsByTable`) |
| Same, exposed on `ZonaiDb` | `apps/zonai/lib/src/db_mutator/zonai_db/zonai_db.dart:832` (`schemaShapes()`) |
| Wire payloads (browser-safe library) | `libs/zonai_schema/lib/payloads.dart` |
| `Where` tree (15 variants) | `libs/zonai_schema/lib/src/types/where.dart` |
| `Where` value normalization (DateTime → ms, bool → 0/1) | `libs/zonai_schema/lib/src/types/where_value.dart` |
| `Update` / `UpdateValue`, and how each variant is applied | `libs/zonai_schema/lib/src/update/` + `table_operations.dart:272` (`_convertUpdateValue`) |
| Column filterability gate | `table_operations.dart:74` (`_requireFilterableColumn`) |
| Ambient token injection + `x-auth` persistence | `libs/zonai_client/lib/src/utils/interceptor.dart` |
| Token storage, admin included | `libs/zonai_client/lib/src/auth.dart`, `admin_auth.dart:24` |
| Server-side `Bearer` parsing for `/db` | `apps/server/lib/src/handlers/db_handler.dart:211` |
| Expand path tree + depth cap | `apps/zonai/lib/src/db_mutator/zonai_db/parts/expand.dart:143` |
| Existing Dart-emitting generators, and where they write | `apps/zonai/lib/src/domain/*/…_generator.dart` → `.dart_tool/zonai/` |
| The hook every `serve`/`db`/`dev` already passes through | `apps/zonai/lib/src/domain/project/project_runtime.dart:36` (`generateProjectEntry()`) |
| Doc-snippet compile check (scans `docs/` **and** `apps/docs/content/`) | `apps/playground/test/doc_snippets_test.dart:367` |

**The inputs already exist.** `TableSchemaShape` is not a new concept invented for
this plan — it is already assembled on every server boot and already shipped to the
admin dashboard. What is missing is an emitter and a decision about where the output
lands.

---

## 2. What is untyped today

From `apps/docs/content/dart-client/database.md`, verbatim:

```dart no-analyze
await client.db.update(
  body: UpdateOneBody(
    table: 'posts',
    updates: [Update.column('title', UpdateValue.literal('New title'))],
    where: Eq('id', 'abc_ps'),
  ),
  fromJson: (row) => row,
);
```

Four classes of bug compile cleanly here, all of them runtime-only today:

1. **Typo'd column** — `Update.column('titel', …)`.
2. **Typo'd or wrong table** — `table: 'post'`.
3. **Cross-table id mixup** — `Eq('id', someAuthorId)` on the `posts` table.
4. **Wrong value type in a filter** — `Eq('created_at', 'yesterday')`.
5. **An `authorization` string without the `Bearer ` prefix** — which does not fail, it
   silently demotes the caller to anonymous (§4.8).

None of these needs a protocol change to fix. They need types over the same wire.

Beyond typos, there are **eight distinct runtime failures the server raises today**
that a generated client can make unrepresentable — see §4.6 and §5.4.

---

## 3. Where the type information comes from

| Source | Fidelity | Cost | Verdict |
| --- | --- | --- | --- |
| **In-process, via `operationsByTable` → `tableSchemaShapeFromTable`** | Complete structure. Loses user Dart type *names*: `IdColumn<PostsId>` flattens to `kind: id`, a Dart enum to `enumValues: [...]` | Low — already assembled | **Chosen** |
| Static analysis of `<schemasPath>/*.dart` | Preserves `PostsId`, `EnumColumn<Status>`, the model class itself | High, and brittle — today's schema discovery is a regex (`operation_generator.dart:15`) | Rejected for v1 |
| `GET /swagger.json` | Route-level only; `table` is a `String` there. Cannot type tables without a new endpoint | — | Rejected for v1; the right path for a future TS/Swift client |

Losing `PostsId` as a *name* costs nothing, because the generated client should mint
its own id types anyway — reaching into the server project's model classes is exactly
what we must not do (§7).

**Decision: generate through an explicit intermediate artifact,
`.zonai/schema.json`.** Codegen then becomes a pure function of that file: golden-file
testable, diffable in review, and retargetable to another language later without
re-solving discovery. The shape map is already `Map<String, TableSchemaShape>` with
`toJson`, so the artifact is nearly free.

```jsonc
// .zonai/schema.json  (sketch)
{
  "version": 1,
  "zonai": "0.7.2",
  "hash": "sha256:8f3c…",           // see §8.2 — build-time gate, not a runtime kill switch
  "tables": { "posts": { /* TableSchemaShape.toJson() */ } }
}
```

---

## 4. Wire-format facts the generator must respect

These are the findings that most shape the generated code. Each was read out of the
server's request/response path, not assumed.

### 4.1 Rows are raw SQLite storage values, not decoded ones

`_list` returns `result.rows.map((e) => e.toMap())` straight through
(`apps/zonai/lib/src/db_mutator/zonai_db/parts/list.dart:68`), and `_sanitizeRows`
only *removes* secret columns and rewrites photo columns
(`.../parts/__utils.dart:701`). Nothing runs the column transformers on the way out.

So on the wire:

| Column kind | JSON value |
| --- | --- |
| `dateTime`, `createdAt`, `updatedAt` | `int` — epoch milliseconds (`DateTimeTransformer.encode`) |
| `boolean`, `isVerified` | `int` — `0` / `1` (`BooleanTransformer`) |
| `enum_` | `String` — the enum's `name` |
| `enumList`, `list`, `map` | JSON-encoded `String` |
| `bigInt` | per `BigIntTransformer` |

**This is the single strongest argument for generating a client.** Every consumer
currently has to know these encodings and re-derive them by hand; a hand-written
`fromJson` that does `json['created_at'] as DateTime` is a runtime crash waiting to
happen, and nothing today tells the author otherwise.

### 4.2 Photo columns are asymmetric: write an id, read a URL

`_resolvePhotoFields` rewrites every photo column into a fully-qualified URL built
from the config's `baseUrl` (`.../parts/resolve_photos.dart:87`), while the write path
validates that the value is an existing photo **id** (`_verifyPhotoIds`, same file).

The generated types should say so: `Uri? photo` on the read model, `PhotoId? photo` on
the create/update builder. Today both are `Object?` in a map, and the asymmetry is
documented nowhere the compiler can see.

### 4.3 Expanded relations are recursive, dotted, and capped at depth 4

`_expandRecord` writes related rows to `row['expanded'][<fkColumnName>]`, keyed by the
**foreign-key column name** (not a relation alias) (`.../parts/expand.dart:73`). The
key is absent entirely when nothing was expanded.

`_ExpandPathTree.fromPaths` splits each requested path on `.` and throws
`ColumnNotExpandableException` past `_maxExpandDepth = 4` (`.../parts/expand.dart:157`).
So `expand: ['author_id', 'author_id.company_id']` is the wire form, and the response
nests the same way: an expanded `authors` row carries its own `expanded` key.

**The response shape is recursive, so the types can be too** — this is why full depth
costs nothing (§5.3).

### 4.4 Some columns are server-filled and must not be required on create

- Ids: `IdColumn.primaryKey() => synthetic ?? generate()` (`id_column.dart:67`).
- `createdAt` / `updatedAt`: collected into `inferredColumns` and written by the
  server (`table_operations.dart:133-145`).
- `isSecret` columns are stripped from every response — a DTO that declares them
  non-nullable fails to parse every row it ever sees.
- `isReadOnly` is already on `ColumnShape`, so all of this is derivable.

### 4.5 `Where` already normalizes values — the generator must not double-encode

`whereValueToJsonEncodable` maps `DateTime → millisecondsSinceEpoch` and
`whereValueToParam` maps `bool → 0/1`, on both the wire and the SQL parameter
(`where_value.dart`). So `Eq('created_at', aDateTime)` is already correct today, and
the generated column tokens should pass values straight through.

One happy consequence: **extension types over `String` erase to `String` at runtime**,
so a generated `PostsId` survives `jsonEncode` and `SendPort.send` untouched. No
custom encoder, and no repeat of the `CastList` isolate hazard documented in
`where_value.dart`.

### 4.6 The server already rejects eight things at runtime that types can reject at compile time

Every one of these is an exception raised from the request path today. Each has a
column-shape fact behind it, so the generator can simply not emit the offending call:

| Server raises | Because | Generator's answer |
| --- | --- | --- |
| `SecretColumnFilterException` | filtering or grouping on a secret column (`_requireFilterableColumn`, `table_operations.dart:74`) | emit **no `ColumnRef`** for `isSecret` columns — the name does not exist |
| `ArgumentError` — increment/decrement on a map column | `_convertUpdateValue`, `table_operations.dart:284` | `MapField` has no `increment` |
| `ArgumentError` — add/remove on a map column | same, `:300` / `:311` | `MapField` has no `add`/`remove` |
| `ArgumentError` — `AddAll` off a list column | same, `:325` | only `ListField` has `addAll` |
| `ArgumentError` — `RemoveAll` off a list column | same, `:333` | only `ListField` has `removeAll` |
| `ArgumentError` — dotted path on a non-map column | `table_operations.dart:187` | only `MapField` exposes `.at(path, …)` |
| `ColumnNotExpandableException` | expanding a column with no FK reference | expand namespace only has getters for real FK columns (§5.3) |
| `ColumnNotExpandableException` | expand path deeper than 4 | depth assert in the path builder |

That table is the real case for full `UpdateValue` coverage (§5.4): modelling the
whole vocabulary does not just add features, it **converts six runtime
`ArgumentError`s into compile errors.**

### 4.7 Map columns support dotted update paths

`ColumnUpdate` accepts `'settings.theme'` and applies a JSON patch, but only on
`MapTransformer` columns — anything else throws (`table_operations.dart:187`). Modelled
as `MapField.at(...)` in §5.5.

### 4.8 Authorization is a raw header, and a missing `Bearer ` prefix fails *open*

Two mechanisms carry the caller's identity, and the generated client inherits both
rather than replacing either:

- **Ambient (the default).** `Interceptor.onRequest` reads the stored token from
  `Auth` and sets `Authorization: Bearer <token>` — but only if the request does not
  already carry one (`interceptor.dart:29`). `Interceptor.onResponse` persists any
  `x-auth` header back to storage. This sits *below* `Db`, so anything the generated
  layer calls is authenticated exactly as `client.db.*` is today.
- **Explicit per-call.** Every `Db` method takes `String? authorization`, which
  `DbDataSourceImpl` sets as a raw header (`gen/src/impls/db_data_source_impl.dart:22`).
  Because the interceptor steps aside when the header is already set, an explicit value
  **wins over the ambient token**. This is how one client instance acts as many
  principals — SSR handling several users, or a test asserting rule behaviour per role.

The trap is in the explicit path. `db_handler._parseBearerAuthorization` requires the
`Bearer ` prefix and, when it is absent, **returns `null` rather than throwing**
(`db_handler.dart:211-217`). So passing a bare JWT does not produce an auth error — the
request proceeds as *unauthenticated*, and what happens next is decided by the table's
rules: a 403 that reads like a permissions bug, or worse, a successful public read that
quietly returns fewer rows than the caller expected. A silent demotion is a strictly
worse failure than a rejection, and it is invisible at the call site today.

**Admin needs nothing special.** `AdminAuth` persists to the same `AuthSession.key` as
ordinary sign-in (`admin_auth.dart:24`), so authenticating as an admin simply replaces
the ambient token. There is no second channel for the generator to model.

---

## 5. Generated output — `posts`, end to end

The playground's table (`apps/playground/lib/src/schemas/posts.dart`) declares, in
order: `id`, `photo`, `author_id` (FK → `authors.id`, cascade), `title`, `body`
(nullable), `created_at`, `updated_at` (nullable). Column order follows declaration
order, matching the shape map — see the snapshot index-order trap in
`docs/known-issues.md`.

**Naming — no singularization** (decided, §10). A table named `posts` produces
`PostsRow`, `PostsExpanded`, `PostsId`, `PostsCreate`, `PostsUpdate`, `PostsApi`,
`PostsExpand`, and the column-token holder `Posts`. Nothing tries to guess an English
singular; `PostsRow` reads correctly at every call site (`List<PostsRow>`,
`Paginated<PostsRow>`) and cannot collide with the token holder.

### 5.1 Ids — one type per table, minted from `kind: id`

```dart no-analyze
extension type const PostsId(String value) {
  static PostsId fromJson(Object? json) => PostsId(json! as String);
  String toJson() => value;
}

extension type const AuthorsId(String value) { /* … */ }
```

`ForeignKeyShape` gives `author_id → authors.id`, so `PostsRow.authorId` is typed
`AuthorsId`. Passing a `PostsId` where an `AuthorsId` belongs stops compiling — for
free, from data the server already publishes.

### 5.2 The read model — recursive, so expansion nests for free

```dart no-analyze
final class PostsRow {
  const PostsRow({
    required this.id,
    required this.authorId,
    required this.title,
    required this.createdAt,
    this.photo,
    this.body,
    this.updatedAt,
    this.expanded,
  });

  final PostsId id;
  final Uri? photo;              // read side is a resolved URL — see §4.2
  final AuthorsId authorId;
  final String title;
  final String? body;
  final DateTime createdAt;      // wire: epoch ms — see §4.1
  final DateTime? updatedAt;
  final PostsExpanded? expanded;

  factory PostsRow.fromJson(Map<String, Object?> json) => PostsRow(
    id: PostsId(_req(json, 'posts', 'id') as String),
    photo: switch (json['photo']) {
      final String url => Uri.parse(url),
      _ => null,
    },
    authorId: AuthorsId(_req(json, 'posts', 'author_id') as String),
    title: _req(json, 'posts', 'title') as String,
    body: json['body'] as String?,
    createdAt: _ms(json, 'posts', 'created_at')!,
    updatedAt: _msOrNull(json, 'posts', 'updated_at'),
    expanded: switch (json['expanded']) {
      final Map<String, Object?> m => PostsExpanded.fromJson(m),
      _ => null,
    },
  );
}

/// One field per expandable FK column. Null unless that column was expanded.
/// `AuthorsRow` carries its own `expanded`, so depth is recursion, not a new type.
final class PostsExpanded {
  const PostsExpanded({this.authorId});
  final AuthorsRow? authorId;

  factory PostsExpanded.fromJson(Map<String, Object?> json) => PostsExpanded(
    authorId: switch (json['author_id']) {
      final Map<String, Object?> m => AuthorsRow.fromJson(m),
      _ => null,
    },
  );
}
```

`_req` / `_ms` are shared runtime helpers that throw a `ZonaiRowParseException` naming
the table, the column, the expected kind and the actual runtime type — never a bare
`TypeError`. This is the load-bearing half of the drift story (§8.2).

### 5.3 Expansion — all four levels, by property chaining

Because the response nests recursively (§4.3), the *types* nest recursively too. The
only new machinery is a path builder, and it is one getter per FK column:

```dart no-analyze
/// Shared runtime.
class ExpandPath {
  const ExpandPath(this.segments)
      : assert(segments.length <= 4, 'Server caps expand depth at 4');
  final List<String> segments;
  String render() => segments.join('.');
}

/// Generated: one class per table, one getter per FK column.
final class PostsExpand extends ExpandPath {
  const PostsExpand(super.segments);
  AuthorsExpand get authorId => AuthorsExpand([...segments, 'author_id']);
}

final class AuthorsExpand extends ExpandPath {
  const AuthorsExpand(super.segments);
  CompaniesExpand get companyId => CompaniesExpand([...segments, 'company_id']);
}
```

```dart no-analyze
final page = await client.posts.list(
  expand: [
    Posts.expand.authorId,             // → 'author_id'
    Posts.expand.authorId.companyId,   // → 'author_id.company_id'
  ],
);

final company = page.items.first.expanded?.authorId?.expanded?.companyId;
```

Each hop is typed by the *referenced* table, so `Posts.expand.authorId.title` does not
compile — `title` is not an FK on `authors`. A self-referencing FK
(`users.manager_id → users.id`) yields `UsersExpand get managerId`, chainable to any
depth in source and bounded by the assert plus the server's own check. **No
combinatorial explosion**: the earlier draft was wrong to claim one, because it
assumed the *return type* had to vary with what you expanded. It doesn't — `expanded`
fields are simply nullable.

### 5.4 Column tokens — typed filters, ordering, and grouping

A single generic `ColumnRef<T>`, with operators added by extension so each is only
reachable on the column types where it is meaningful:

```dart no-analyze
final class ColumnRef<T> {
  const ColumnRef(this.name);
  final String name;

  Where eq(T value) => Eq(name, value);
  Where inList(List<T> values) => In(name, values);
  Where notIn(List<T> values) => NotIn(name, values);
  OrderByTerm get asc => OrderByTerm(column: name, direction: SortDirection.asc);
  OrderByTerm get desc => OrderByTerm(column: name, direction: SortDirection.desc);
}

extension ComparableColumnRef<T extends Comparable<Object?>> on ColumnRef<T> {
  Where gt(T value) => Gt(name, value);
  Where gte(T value) => Gte(name, value);
  Where lt(T value) => Lt(name, value);
  Where lte(T value) => Lte(name, value);
}

extension StringColumnRef on ColumnRef<String> {
  Where contains(String value) => Contains(name, value);
  Where startsWith(String value) => StartsWith(name, value);
  Where endsWith(String value) => EndsWith(name, value);
}

extension NullableColumnRef<T> on ColumnRef<T?> {
  // NOT `Null(name)` / `NotNull(name)` — see §8.1. `Where.isNull` and
  // `Where.isNotNull` are new redirecting factories on the sealed base, so the
  // generated code never has to name the `Null` class and never has to import
  // it.
  Where get isNull => Where.isNull(name);
  Where get isNotNull => Where.isNotNull(name);
}
```

Those two factories do not exist yet; adding them to `where.dart` is part of the
§8.1 work:

```dart no-analyze
sealed class Where {
  const Where();
  factory Where.isNull(String column) = Null;
  factory Where.isNotNull(String column) = NotNull;
  // … the existing variants are unchanged.
}
```

This is not stylistic. `where.dart:111` declares `final class Null extends Where`,
which **shadows `dart:core`'s `Null`** in any library importing `payloads.dart`
unfiltered — so `Null` and `NotNull` stay off the consumer barrel (§8.1) and the
generated code reaches the same two `Where` nodes through the base class instead.

```dart no-analyze
abstract final class Posts {
  static const table = 'posts';
  static const expand = PostsExpand([]);

  static const id = ColumnRef<PostsId>('id');
  static const photo = ColumnRef<Uri?>('photo');
  static const authorId = ColumnRef<AuthorsId>('author_id');
  static const title = ColumnRef<String>('title');
  static const body = ColumnRef<String?>('body');
  static const createdAt = ColumnRef<DateTime>('created_at');
  static const updatedAt = ColumnRef<DateTime?>('updated_at');
  // No token is emitted for a secret column — see §4.6.
}
```

`Posts.body.isNull` compiles; `Posts.title.isNull` does not. `Posts.title.contains(…)`
compiles; `Posts.createdAt.contains(…)` does not. `Posts.createdAt.gt(aDateTime)`
compiles and serializes correctly with no work, per §4.5.

**`groupBy` is modelled, not passed through.** The server takes a single column name
and validates it with `_requireFilterableColumn` before handing it to
`builder.groupBy` (`table_operations.dart:709-717`) — it does not add aggregates, so
the rows come back in the ordinary row shape and `PostsRow.fromJson` still applies. So
the typed form is exactly a `ColumnRef`:

```dart no-analyze
await client.posts.list(groupBy: Posts.authorId);
```

Because secret columns get no token at all, `SecretColumnFilterException` becomes
unreachable through the generated API — in filters *and* in `groupBy`.

Every operator returns a plain `Where` / `OrderByTerm` / column name, so **nothing on
the wire changes and the server needs no work at all.**

### 5.5 Write builders — full `UpdateValue` coverage, four shared classes

The naive design (`PostsUpdate({String? title})`) has two defects: it can only express
`literal`, and it **cannot distinguish "leave alone" from "set to NULL"** — even
though `Literal(null)` is a real operation the server applies
(`_convertUpdateValue`, `table_operations.dart:282`).

Both are fixed by one idea: each field takes a small `Patch` value rather than a raw
one. The operation vocabulary lives in **four shared runtime classes written once**,
and the generator emits *one line per field*:

```dart no-analyze
/// Shared runtime — not generated.
sealed class Patch<T> {
  const Patch(this.value);
  final UpdateValue value;
}

/// Any column.
final class Field<T> extends Patch<T> {
  Field.set(T v) : super(Literal(v));
  const Field.clear() : super(const Literal(null));
}

/// integer / real / bigInt columns.
final class NumField<T extends num> extends Patch<T> {
  NumField.set(T v) : super(Literal(v));
  const NumField.clear() : super(const Literal(null));
  const NumField.increment() : super(const Increment());
  const NumField.decrement() : super(const Decrement());
  NumField.add(T v) : super(Add(v));
  NumField.subtract(T v) : super(Remove(v));
}

/// list / enumList / photos columns.
final class ListField<E> extends Patch<List<E>> {
  ListField.set(List<E> v) : super(Literal(v));
  const ListField.clear() : super(const Literal(null));
  ListField.add(E v) : super(Add(v));
  ListField.remove(E v) : super(Remove(v));
  ListField.addAll(List<E> v) : super(AddAll(v));
  ListField.removeAll(List<E> v) : super(RemoveAll(v));
}

/// map columns — including the dotted JSON path form (§4.7).
final class MapField<T> extends Patch<T> {
  MapField.set(T v) : super(Literal(v));
  const MapField.clear() : super(const Literal(null));
  // `.at()` renders to a dotted ColumnUpdate rather than a plain one.
}
```

The generator picks the class per column straight from `ColumnShapeKind`, so the
per-table output stays mechanical:

```dart no-analyze
final class PostsUpdate {
  const PostsUpdate({this.authorId, this.title, this.body, this.photo});

  final Field<AuthorsId>? authorId;
  final Field<String>? title;
  final Field<String>? body;
  final Field<PhotoId>? photo;

  List<Update> toUpdates() => [
    if (authorId case final p?) ColumnUpdate('author_id', p.value),
    if (title case final p?) ColumnUpdate('title', p.value),
    if (body case final p?) ColumnUpdate('body', p.value),
    if (photo case final p?) ColumnUpdate('photo', p.value),
  ];
}
```

Two lines of generated code per column, whatever the vocabulary. Call sites:

```dart no-analyze
await client.posts.update(
  where: Posts.id.eq(PostsId('abc_ps')),
  set: PostsUpdate(title: Field.set('New title')),
);

// Clear a nullable column — not expressible in the naive design at all.
await client.posts.update(
  where: Posts.id.eq(PostsId('abc_ps')),
  set: const PostsUpdate(body: Field.clear()),
);

// Numeric and list vocabularies, on the columns that actually support them.
await client.articles.update(
  where: Articles.id.eq(id),
  set: const ArticlesUpdate(viewCount: NumField.increment()),
);
await client.articles.update(
  where: Articles.id.eq(id),
  set: ArticlesUpdate(tags: ListField.add('dart')),
);
```

The cost is `Field.set('x')` where a bare `'x'` would have done. That is the price of
distinguishing NULL from absent, and of gating the vocabulary by column kind; it buys
the six compile errors in §4.6. **`Field.set('x')` ships as-is** (decided, §10.6). A
`.set` extension getter on common value types (`'New title'.set`) remains available as
a sweetener if the explicit form grates in practice — it changes nothing structural,
which is exactly why it is deferred rather than built now.

Create is unchanged and stays plain — there is no absent/NULL ambiguity on insert:

```dart no-analyze
final class PostsCreate {
  const PostsCreate({
    required this.authorId,
    required this.title,
    this.body,
    this.photo,               // PhotoId on write — see §4.2
  });
  // … toObject() → Map<String, dynamic> …
}
```

### 5.6 The per-table API

```dart no-analyze
final class PostsApi {
  const PostsApi(this._db);
  final Db _db;

  Future<PostsRow> get(PostsId id, {List<ExpandPath> expand = const []}) =>
      _db.get(
        body: GetBody(
          table: Posts.table,
          where: Posts.id.eq(id),
          expand: [for (final e in expand) e.render()],
        ),
        fromJson: PostsRow.fromJson,
      );

  Future<Paginated<PostsRow>> list({
    Where? where,
    int? limit,
    int? offset,
    List<OrderByTerm>? orderBy,
    ColumnRef<Object?>? groupBy,
    List<ExpandPath> expand = const [],
  }) => _db.list(
        body: ListBody(
          table: Posts.table,
          where: where,
          limit: limit,
          offset: offset,
          orderBy: orderBy,
          groupBy: groupBy?.name,
          expand: [for (final e in expand) e.render()],
        ),
        fromJson: PostsRow.fromJson,
      );

  Future<int> count({Where? where}) => /* … */;
  Future<PostsRow> create(PostsCreate data) => /* … */;
  Future<PostsRow> update({required Where where, required PostsUpdate set}) => /* … */;
  Future<void> delete(PostsId id) => /* … */;

  PostsListen get listen => PostsListen(_db.listen);
}

final class PostsListen {
  const PostsListen(this._listen);
  final DbListen _listen;

  Stream<PostsRow> one(Where where) => /* … */;
  Stream<List<PostsRow>> list({Where? where, int? limit, ColumnRef<Object?>? groupBy}) => /* … */;
  Stream<int> count({Where? where}) => /* … */;
}
```

`StreamListBody` carries `groupBy` too (`stream_list_body.dart:20`), so the streaming
mirror takes the same typed argument.

### 5.7 What the caller writes

```dart no-analyze
final page = await client.posts.list(
  where: Posts.title.startsWith('Hello'),
  orderBy: [Posts.createdAt.desc],
  limit: 20,
  expand: [Posts.expand.authorId.companyId],
);

for (final post in page.items) {
  print('${post.title} by ${post.expanded?.authorId?.name}');
  print(post.expanded?.authorId?.expanded?.companyId?.name);
  print(post.createdAt.toIso8601String());   // already a DateTime
}
```

Compare to §2. No table strings, no column strings, no `fromJson`, no epoch-ms
arithmetic, no map literal.

### 5.8 Authorization — inherited unchanged, but no longer a bare `String`

**Nothing about how auth works changes, and nothing should.** The generated layer sits
on top of `Db`, which sits on top of the interceptor (§4.8), so the ambient path is
automatic: `client.posts.list()` carries the stored token exactly as
`client.db.list(...)` does. There is nothing to generate for the common case, and
signing in as an admin needs no separate API.

What the generated methods *must* keep is the explicit override — an earlier draft of
this document silently dropped `authorization` from every signature, which would have
made the typed client strictly less capable than the generic one and cut off SSR and
role-based tests entirely. It is restored on every method.

It should not be restored as a `String`, though. Given §4.8 — prefix required, missing
prefix fails open — a raw string is precisely the kind of unchecked value this whole
project exists to remove. So the generator emits a wrapper that cannot be built wrong:

```dart no-analyze
/// Shared runtime. Erases to `String` at runtime (§4.5), so the wire is unchanged.
extension type const Authorization._(String header) {
  /// Wraps a bare access token with the `Bearer ` prefix the server requires.
  factory Authorization.bearer(String token) => Authorization._('Bearer $token');

  /// Escape hatch for a header value that is already complete.
  const Authorization.raw(String header) : this._(header);
}
```

Every generated method takes it as a named optional, defaulting to ambient:

```dart no-analyze
Future<Paginated<PostsRow>> list({
  Where? where,
  int? limit,
  Authorization? as,      // omit → the interceptor's stored token
  /* … */
});
```

```dart no-analyze
// Ambient: whoever is signed in on this client.
final mine = await client.posts.list(where: Posts.authorId.eq(me));

// Explicit: act as a specific principal, e.g. inside an SSR request handler.
final theirs = await client.posts.list(
  where: Posts.authorId.eq(them),
  as: Authorization.bearer(tokenFromCookie),
);
```

`Authorization.bearer` makes the missing-prefix demotion unrepresentable, which is the
ninth entry the §4.6 table would carry if it covered auth as well as columns — and the
only one on that list whose failure mode is *silent*.

One scoped caveat, stated precisely so it is not read as broader than it is:
`Interceptor.onResponse` persists an `x-auth` header unconditionally, but only
`auth_controller.dart` ever emits that header — **no `/db` route does**. So a
`client.posts.*` call carrying an explicit `as:` cannot clobber the client's stored
token. The hazard exists only when an *auth* route is called with an explicit
authorization on a shared client instance, which is outside the generated surface.

---

## 6. Integration — an extension, not a fork

`ZonaiClient` is a plain class with a public `db` field
(`libs/zonai_client/lib/src/zonai_client.dart:114`). That is all the generated layer
needs:

```dart no-analyze
// generated
extension ZonaiTables on ZonaiClient {
  PostsApi get posts => PostsApi(db);
  AuthorsApi get authors => AuthorsApi(db);
  CompaniesApi get companies => CompaniesApi(db);
}
```

Import the generated library and `client.posts` exists. The dependency arrow points
**generated → `zonai_client`** and never back, so:

- `zonai_client` ships completely unchanged and stays publishable on its own.
- Projects that want nothing to do with codegen keep the current generic API, which
  remains the escape hatch for anything the generator does not cover.
- The two can coexist in one file: `client.posts.list(...)` and
  `client.db.list(body: ListBody(table: 'posts'), …)` are both valid.

---

## 7. Configuration — everything in `zonai.yaml`, nothing required on the CLI

The server project **cannot** be an app dependency: `zonai_schema`'s main library
pulls native SQLite (which is why `payloads.dart` exists as the browser-safe subset),
and `zonai` must never appear in an app's `pubspec.yaml`. So the generator writes into
a directory the app owns — and every knob lives in config, with CLI flags as
overrides only:

```yaml
# zonai.yaml
client:
  output: ../app/lib/gen/zonai   # required for `zonai gen client` to do anything
  package: false                 # true → also emit a pubspec.yaml
  packageName: my_api            # only read when package: true
  tables:
    exclude: [audit_log]         # default: every registered table
  names:
    posts:
      row: BlogPostsRow          # per-table override of the §5 naming scheme
```

```sh
zonai gen client                 # reads zonai.yaml, no arguments needed
zonai gen client --check         # exits non-zero if the output is stale (§8.2)
zonai gen client --output <dir>  # override, for one-off/CI use
zonai gen client --force         # write into a directory we cannot prove we own
```

**The write guard is by provenance, not by location** (decided, §10.7). The hazard is
`client.output` pointed at a hand-written `lib/` and silently clobbering it. A
repo-root rule does not catch that and does catch the primary use case —
`../app/lib/gen/zonai` is outside the repo *by construction*, so a location guard
would make the opt-out mandatory boilerplate that nobody reads, which is worse than no
guard at all. Instead the generator establishes ownership of what it writes:

- every generated file carries a generated-code header (`// GENERATED BY `zonai gen
  client` — DO NOT EDIT`), so a human who opens one knows;
- the generator writes a **manifest** into the output directory listing every file it
  produced, so it can tell its own output from anything else;
- it **refuses to write into a non-empty directory that has no manifest**, and names
  what it found. `--force` is the acknowledged override.

An empty directory writes freely, and a directory the generator already owns is
rewritten freely — including deleting files the manifest lists but the current schema
no longer produces, which a location rule could never do safely. The only case that
stops is the one that is actually dangerous: files present that we cannot prove we
wrote.

This mirrors how `schemasPath` / `operationsPath` / `rulesPath` already work today
(`zonai.yaml` at the repo root), so `client:` is a new key in a file that already
exists rather than a new mechanism. `zonai gen client` with no `client:` block errors
with a message showing the block to add.

Regeneration hooks where `generateProjectEntry()` already runs
(`project_runtime.dart:36`), plus the `dev` watcher on `schemasPath`, so the typed
client tracks the schema while you work. A new `gen` entry is needed in
`commandNeedsProjectRuntime` (`project_runtime.dart:26`) so the command re-execs into
the project-linked entry that can see the user's tables.

---

## 8. Prerequisites and risks

### 8.1 Export gaps block this — BLOCKER (narrower than r2 claimed)

**r2 got two things wrong here, and they are corrected rather than edited out.**

**Retraction — the `Id` claim.** r2 said `Id` is "likewise absent from `payloads.dart`"
and implied the generator needs it exported. It does not need it at all. §5.1 mints
one id type per table as `extension type const PostsId(String value)` over a plain
`String` — nothing implements `Id`, nothing mentions it. Read against the source:

- `libs/zonai_client/lib` contains **zero** occurrences of the token `Id`
  (`grep -rnw Id libs/zonai_client/lib` → no matches). The typed client has never
  referred to it.
- Every importer of `libs/zonai_schema/lib/src/types/id.dart` is server-side:
  `zonai_schema`'s own internals (`cron_jwt.dart:1`, `provisioning_jwt.dart:1`,
  `push_message.dart:3`, `jwt_id.dart:1`, `jwt.dart:5`, `schemas/auth_table.dart:6`,
  `column_types/id_column.dart:2`), the server-side barrel
  (`zonai_schema.dart:90`, **not** `payloads.dart`), and tests under `apps/zonai` and
  `apps/server`. No client-side importer exists.

So `Id` being off `payloads.dart` is not a gap; it is correct. It is a server-side
identity abstraction, and the generated client's ids are a different mechanism that
happens to share a noun. Nothing in this plan should add it.

**Narrowing — the `Where`/`Update` half is a `show`-list edit, not new plumbing.**
r2 listed `Where`, `Eq`, `Gt`, `In`, `And`, `Or`, `OrderByTerm`, `SortDirection`,
`Update` and the `UpdateValue` family as things `payloads.dart` would have to start
exporting. It already exports all of them:

- `export 'src/types/where.dart'` → `Where` and all 15 variants;
- `export 'src/types/order_by.dart'` → `SortDirection`, `OrderByTerm`;
- `export 'src/update/update.dart'` → `Update`, `ColumnUpdate`, `ObjectUpdate`, and —
  since `update_value.dart` is a `part` of that library, not a separate one — the
  whole `UpdateValue` family (`Literal`, `Increment`, `Decrement`, `Add`, `Remove`,
  `AddAll`, `RemoveAll`) with it.

The only thing hiding them from consumers is `zonai_client`'s own explicit `show` list
in `libs/zonai_client/lib/zonai_client.dart`. So this half is **adding names to one
`show` list**, with no change to `zonai_schema` at all.

**What genuinely is missing** is the other half r2 named, and it is exactly five
`lib/src` types — the five already recorded as `GAP -- … (unfixed)` in
`libs/zonai_client/test/export_surface_test.dart`'s `_exclusions`: `Db`, `DbListen`,
`Emails`, `Photos`, `AdminAuth`. The generated `PostsApi` must *name* `Db` and
`DbListen` to hold them. These are the API-design calls that sweep deliberately
deferred; adding them is a decision, not a chore, and this plan forces it.

**A constraint the `show` list turns up — `Null` is not exportable.**
`where.dart:111` declares `final class Null extends Where`, which **shadows
`dart:core`'s `Null`** in any library importing `payloads.dart` unfiltered. Verified,
not reasoned: compiling `Null x;` in a library with that import fails with
`not_assigned_potentially_non_nullable_local_variable` — i.e. `Null` resolved to the
`Where` subclass, which is non-nullable, rather than `dart:core`'s, which would have
been fine. A non-`dart:core` import wins over the implicit one, so every consumer of
an unfiltered barrel silently loses the real `Null`.

`Null` and `NotNull` therefore stay **off** the consumer `show` list, and §5.4's
`isNull` / `isNotNull` build through new `Where.isNull` / `Where.isNotNull`
redirecting factories on the sealed base instead. The generated code never names the
class, so nothing it emits can leak the shadow into a consumer's namespace. This costs
two factory lines in `where.dart` and is the reason §5.4's `NullableColumnRef` reads
the way it does.

### 8.2 Drift — a build-time gate, never a runtime kill switch

**The first draft of this document proposed failing requests on a schema-hash
mismatch. That was wrong and it is retracted.** A shipped mobile app cannot be
force-updated; a client that refuses to talk to a server whose schema hash differs
turns a *backward-compatible* change — adding a table, adding a nullable column — into
a total outage for every user who has not updated. Hash equality is the wrong
predicate, because almost every schema change a client survives changes the hash.

The corrected design has three layers, and only the first one is allowed to fail hard:

**Build time — hard failure, where it costs nothing.**
`zonai gen client --check` regenerates into a temp dir and exits non-zero if the
committed output differs from what the current schema produces. That runs in CI and in
the release gate; drift is caught before it ships, by the person who caused it. This
is where a hash comparison is exactly right, because both sides are the same commit.

**Runtime — passive diagnostic only, never a block.**
The server advertises its schema hash (a response header, or a field on `/health`).
The client records it, compares it once, and if it differs it reports through a
callback — `onSchemaDrift(local, remote)` — that defaults to a single log line.
It **never throws, never retries, never blocks a request.** An older app on a newer
server keeps working for every field it already knew about, which is the whole point.
A strict mode exists but is opt-in and off in release:

```dart no-analyze
final client = ZonaiClient(
  schemaDrift: SchemaDriftPolicy.warn,   // .ignore | .warn (default) | .fail
  onSchemaDrift: (local, remote) => analytics.log('zonai.schema_drift'),
);
```

**Parse time — the layer that actually protects the app.**
The real hazard is not "the hash differs", it is "a column I expected is gone or
changed kind". Generated `fromJson` runs through shared helpers (§5.2) that raise
`ZonaiRowParseException` naming table, column, expected kind and actual runtime type.
That works regardless of version skew, needs no server cooperation, and turns the
failure the first draft was worried about — "null-cast errors deep inside a
`fromJson`" — into a diagnosable, reportable one. This is the part worth building
first.

**What none of this catches:** a change that keeps a column's shape but changes its
*meaning* — a status string whose set of values shifts, a column repurposed. The hash
moves, so `--check` flags it at build time, but nothing at runtime can tell a
semantically-changed `String` from an unchanged one. Schema compatibility across
versions remains the server's contract to keep; this machinery only makes breaking it
visible.

### 8.3 Types say nothing about permission — RISK

`canView` / `canList` / `canUpdate` still reject at runtime. A typed API reads as a
guarantee and must not be allowed to imply one — this belongs in the generated file's
header comment and in the docs page, not only here.

### 8.4 Constraints and known gaps

- **Views** (`isView: true` on the shape) are read-only — emit `get`/`list`/`count`
  only, no create/update/delete.
- **Secrets** are modelled as absent, not nullable-and-usually-null (§4.4), and get no
  `ColumnRef` at all (§4.6).
- **Custom operations** are enumerable (`BaseRowRules.customOperationNames`,
  `base_row_rules.dart:68`) but nothing describes their return shape, so
  `client.posts.custom.publish(…)` cannot be typed without new authoring metadata.
  That overlaps issue #25 — out of scope here.
- **`MapField.at()`** needs a path type; v1 can accept a `List<String>` and validate
  nothing beyond "this is a map column", which the type already guarantees.
- **Id-type collisions across packages** — see §10.4. Detectable within one generation
  run, invisible across two.

---

## 9. Phasing

| Phase | Contents |
| --- | --- |
| **1** | `zonai gen client` reading the `client:` block; `.zonai/schema.json`; ids, read models with the §5.2 parse helpers, `ZonaiTables` extension, `get`/`list`/`count`, and the `Authorization` wrapper on every method (§5.8). Fix the §8.1 exports. Golden-file tests over the playground's six tables. |
| **2** | `ColumnRef` tokens; typed `Where` / `OrderByTerm` / `groupBy`; the `Patch` family and `PostsCreate` / `PostsUpdate`; create, update, delete. |
| **3** | `ExpandPath` chaining to full depth 4; recursive `expanded` models; `listen` mirrors; `--check` wired into the Test workflow (§10.5); a compiled-binary `gen client` smoke in `verify-release.yml`; `dev`-watch regeneration. |
| **4** | Enum columns as real Dart enums; `MapField.at()` paths; custom operations (pending #25); retarget the same `schema.json` to TypeScript. |

**On that phase-3 release-gate smoke.** `--check` itself belongs in the Test workflow
and only there (§10.5), but there is one thing no source-tree test can catch: *the
shipped binary cannot generate*. `verify_build_command.sh` already exercises exactly
that shape for `zonai build`, so a `gen client` equivalent is a known, proven pattern
rather than a new mechanism. It is phase 3 and not phase 1 because the `cli` leg's
wall-clock is already the binding constraint on that workflow — `cli` is budgeted at
`timeout-minutes: 35` against 10 for every other job in `test.yml`, and the compiled
binary runs are what fill it. Adding a five-platform binary invocation to the release
path is worth doing once the generator exists and is stable; it is not worth paying
for while the output shape is still moving.

Phase 1 is independently useful: it removes the hand-written `fromJson` and the
epoch-ms/0-1 decoding from every consumer, which is where the runtime bugs actually
live, and it delivers the parse-time diagnostics that §8.2 identifies as the real
protection.

---

## 10. Decisions

Recorded rather than left open, so a reader does not re-litigate them.

**10.1 Model naming — no singularization.** `posts` → `PostsRow`, not `Post`. No
English guessing, no irregular-plural table, no surprise when a table is already
singular. The token holder keeps the bare name (`Posts`) since it reads as a namespace,
and `names.<table>.row` in `zonai.yaml` overrides per table (§7).

**10.2 Dependency shape — not load-bearing.** Whether the generated package imports
`zonai_schema/payloads.dart` directly or only re-exports through `zonai_client` is an
implementation detail; go with whatever falls out of the §8.1 export decision.

**10.3 Update vocabulary — full coverage.** All seven `UpdateValue` variants, gated by
column kind through four shared `Patch` classes, at a cost of two generated lines per
column (§5.5). This was the right call for a reason beyond completeness: it makes six
of the server's runtime `ArgumentError`s unreachable (§4.6), and it fixes the
absent-vs-NULL ambiguity that the naive builder could not express at all.

**10.4 Id collisions — the developer's call, with a warning where we can see one.**
Each project generates its own client, so two projects in one workspace can each mint a
`UsersId`; that is resolved at the import site with a prefix, by the developer.
The generator warns on what it can actually see — two tables in **one generation run**
resolving to the same Dart type name after `names` overrides are applied. It cannot see
another project's output, so a cross-package collision surfaces as an ordinary Dart
import conflict. Saying so plainly is better than implying a guard that does not exist.

**10.5 `--check` runs in the Test workflow only — not on the release gate.**
`--check` compares committed generated output against the current schema. That is a
**source-tree drift** check, and PR-time CI is what source-tree drift checks are for.
§8.2 already states the principle — drift is "caught before it ships, **by the person
who caused it**" — and putting `--check` on the release gate inverts exactly that: the
drift would surface at release time, in front of whoever is releasing, who is usually
not whoever caused it. `test.yml` runs on `pull_request`; that is the right door.

`verify-release.yml` is also simply not a source-drift gate, and reading it says so.
Every job there downloads a **compiled binary artifact** and exercises it —
`verify_release_artifact.sh`, `verify_build_command.sh`, a cross-target bundle run, a
previous-release compatibility check. It is per-sha and `workflow_dispatch`-sensitive,
and `docs/releasing.md`'s Rule zero ("if `verify-release.yml` is red for the commit you
are about to release, you do not have a release candidate") means every addition there
costs real release friction: a new way for the gate to go red is a new way for a
release to stop.

The one genuine counter-argument, recorded rather than buried: a compiled-binary
`gen client` smoke in `verify-release.yml` would catch "the shipped binary cannot
generate", which no source test can, and `verify_build_command.sh` already does exactly
that for `zonai build`. That is real, and it is why it is on the phase-3 row in §9
alongside "`--check` wired into CI" — not a phase-1 change, and not the same thing as
putting `--check` on the gate.

**10.6 `Field.set('x')` ships as-is; no `.set` extension.** It is self-describing at
the call site, and — the deciding point — the extension stays purely **additive**.
Adding it later changes nothing structural, so shipping without it is the reversible
choice and shipping with it is not. Generating a `.set` getter on `String`, `int`,
`bool` and `DateTime` up front puts a very generic member on core types across every
consumer's namespace, in every file that imports the generated library, before anyone
has complained about the explicit form. If the explicit form does grate in practice,
the sweetener is a small additive change made with evidence. §5.5 describes it as
deferred, not pending.

**10.7 `zonai gen client` guards by provenance, not by location.** No repo-root rule.
`../app/lib/gen/zonai` is outside the repo *by construction* (§7) — the server project
cannot be an app dependency, so writing into a directory the app owns is the primary
use case, not an edge case. A location guard blocks it, and the opt-out flag then
appears on every invocation, which is how a guard becomes boilerplate nobody reads and
protects nothing.

The hazard worth blocking is different and more specific: `client.output` pointed at a
hand-written `lib/` and silently clobbering it. Location tells you nothing about that.
Provenance does — a generated-code header on every file, a manifest of what the
generator wrote, and a refusal to write into a **non-empty directory with no manifest**
unless `--force`. That leaves the intended layout completely unobstructed, and it also
buys something a location rule could not: the generator can safely delete its own
stale output, because the manifest says which files are its. §7 carries this as
designed behaviour.

---

## 11. Revision history

**r3** — closes the last three open questions, and corrects r2 against the source:

- **`--check` goes in the Test workflow only** (§10.5), not the release gate. It is a
  source-tree drift check and PR-time CI is where those belong; §8.2's own principle —
  caught by the person who caused it — is inverted by a release-time check. Reading
  `verify-release.yml` settled it: every job there downloads and exercises a compiled
  binary, so `--check` would be the only source-drift job in a workflow that has none,
  behind Rule zero. The real release-gate item is a **compiled-binary `gen client`
  smoke** mirroring `verify_build_command.sh`, recorded as phase 3 in §9 with the
  reason it is not phase 1 (the `cli` leg's wall-clock is already the binding
  constraint — 35 minutes budgeted against 10 everywhere else).
- **`Field.set('x')` ships as-is** (§10.6). The `.set` extension is purely additive, so
  not building it is the reversible call; building it up front puts a very generic
  member on `String`/`int`/`bool`/`DateTime` across every consumer's namespace before
  anyone has complained. §5.5 now reads *deferred*, not *pending*.
- **The output guard is by provenance, not location** (§10.7, folded into §7 as
  designed behaviour). A repo-root rule blocks the primary use case —
  `../app/lib/gen/zonai` is outside the repo by construction — and turns its own
  opt-out into boilerplate. A generated-code header, a manifest, and a refusal to write
  into a non-empty unmanifested directory block the hazard that actually exists
  (clobbering hand-written `lib/`) and additionally make it safe to delete stale output.
- **r2's `Id` claim is retracted** (§8.1). r2 said `Id` was missing from
  `payloads.dart` and implied the generator needs it. It does not: §5.1 mints ids as
  extension types over `String`, `libs/zonai_client/lib` contains zero occurrences of
  the token, and every importer of `src/types/id.dart` is server-side. Kept visible
  here rather than edited out, the same way r1's runtime-hash mistake is.
- **The rest of the §8.1 gap is narrower than r2 stated.** `payloads.dart` already
  exports `where.dart`, `order_by.dart` and `update/update.dart` — and `update_value
  .dart` is a `part` of the last, so the whole `UpdateValue` family comes with it. The
  `Where`/`Update` half is therefore a `show`-list edit in `zonai_client`, not new
  plumbing; the genuine gap is exactly the five `lib/src` types already recorded as
  unfixed in `export_surface_test.dart`'s `_exclusions` (`Db`, `DbListen`, `Emails`,
  `Photos`, `AdminAuth`).
- **New constraint, found by making that export decision:** `where.dart:111`'s
  `final class Null extends Where` **shadows `dart:core`'s `Null`** for anyone
  importing `payloads.dart` unfiltered — verified by compiling `Null x;` against that
  import and getting `not_assigned_potentially_non_nullable_local_variable`. `Null` and
  `NotNull` stay off the consumer barrel, and §5.4's `isNull`/`isNotNull` now build
  through new `Where.isNull` / `Where.isNotNull` redirecting factories instead.

**r2** — supersedes r1 after review:

- **Expansion goes to the server's full depth of 4**, not one level. r1 claimed nesting
  was "combinatorial in the type system"; that was wrong. It is only combinatorial if
  the return type varies with what you expanded. Keeping `expanded` fields nullable
  makes depth pure recursion, and property chaining (§5.3) types the paths.
- **`groupBy` is modelled** (§5.4) rather than passed through untyped. Reading the
  server showed it takes a single filterable column and does not change the row shape,
  so a `ColumnRef` is an exact fit.
- **The drift design is retracted and rebuilt** (§8.2). r1's runtime hash check would
  have broken every un-updated app on a backward-compatible schema change. Hard
  failure moved to build time; runtime is passive; per-field parse diagnostics do the
  real work.
- **Configuration moved into `zonai.yaml`** (§7); no CLI argument is required.
- **Update builders cover the full `UpdateValue` vocabulary** (§5.5) through four
  shared `Patch` classes, which also fixed an absent-vs-NULL defect r1 did not notice.
- **Naming settled on no singularization** (§10.1), and the four r1 open questions are
  now decisions (§10).
- Added §4.6 — the eight runtime exceptions the generated API can make unreachable —
  which is the clearest single statement of what this work buys.
- **Authorization restored to every generated signature** (§5.8), after r1 dropped it
  without saying so — that would have made the typed client less capable than the
  generic one. Typing it as `Authorization` rather than `String` closes the
  fails-*open* missing-`Bearer ` hole documented in §4.8, the only failure on this
  document's list that is silent rather than loud.
