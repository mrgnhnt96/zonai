---
title: Typed Client
description: The generated, per-table client — typed rows, typed ids, and no table-name strings.
---

`zonai gen client` generates a Dart client from your schema, so application code names tables as properties and gets decoded rows back:

```dart no-analyze
final page = await client.posts.list(
  where: Eq('author_id', authorId.value),
  orderBy: [OrderByTerm(column: 'created_at', direction: SortDirection.desc)],
  limit: 20,
);

for (final post in page.items) {
  print(post.title);          // String, not Object?
  print(post.createdAt);      // DateTime, decoded from epoch millis
}
```

Compare that with the untyped equivalent, which stays available and valid:

```dart no-analyze
final page = await client.db.list(
  body: ListBody(table: 'posts', limit: 20),
  fromJson: (row) => row,     // Map<String, dynamic> — decode it yourself
);
```

Generate it with [`zonai gen client`](/cli/gen); configure it with the [`client:` block](/configuration/zonai-yaml#client-settings).

## It extends the client, it does not replace it

The generated code hangs off `ZonaiClient` as an extension. The dependency arrow points *generated → `zonai_client`* and never back, so both styles are valid in the same file:

```dart no-analyze
import 'package:my_app/gen/zonai/zonai_client.g.dart';

final typed = await client.posts.list();
final raw = await client.db.list(
  body: ListBody(table: 'posts'),
  fromJson: (row) => row,
);
```

You keep `client.auth`, `client.photos`, `client.email` and `client.db.listen` exactly as they were.

<Warning>

**The generated API covers reads, writes and live queries** — `get` / `list` / `count`, the six mutations, and `listen.one` / `listen.list` / `listen.count`. `client.db` remains valid for anything the generator deliberately leaves untyped, such as filtering a JSON-encoded column. A method's absence here is always a decision with a reason, never a gap: a view has no write surface, and a `bigInt` column has no token or write field because the request would throw.

</Warning>

## What is generated per table

For a table `posts` you get these names, all derived from one stem:

| Name | What it is |
|------|-----------|
| `PostsRow` | One decoded row — `String`, `DateTime`, `bool`, lists and maps, not raw storage |
| `PostsId` | An extension type over `String` for that table's id |
| `PostsApi` | `get` / `list` / `count` and the [write surface](#creating-updating-and-deleting) |
| `PostsCreate` / `PostsUpdate` | The [write builders](#creating-updating-and-deleting) |
| `Posts` | The [column tokens](#filtering-and-ordering-by-column-token) — `Posts.title`, `Posts.createdAt` |
| `client.posts` | The accessor, added by an extension on `ZonaiClient` |

Rename them all at once with [`names.<table>.row`](/configuration/zonai-yaml#client-settings) — an override that moved one name out of four would be no escape hatch at all for the case that most needs one, a table name that is not a usable Dart identifier.

## What each column becomes

The row type is where the generator earns its keep: values arrive from the server in SQLite's storage encodings, and the generated `fromJson` decodes them so you never write `json['created_at'] as DateTime` and find out at runtime.

| Column kind | Field type |
|---|---|
| `id` | the table's own id type, or the **target table's** id for a foreign key |
| `text`, `email` | `String` |
| `integer` | `int` |
| `real` | `double` |
| `boolean`, `isVerified` | `bool` — from `0` / `1` on the wire |
| `bigInt` | `BigInt` |
| `dateTime`, `createdAt`, `updatedAt` | `DateTime` — from epoch milliseconds |
| `enumerator` | `BooksShelf` — a per-column extension type, see below |
| `enumList` | `List<BooksTags>` — same, per element |
| `list` | `List<Object?>` — see below |
| `map` | `Map<String, Object?>` |
| `blob` | `List<int>` |
| `photo` | `Uri` |
| `photos` | `List<Uri>` |

A nullable column gets the nullable form (`double?`, `DateTime?`).

### Secret columns are not generated at all

A `PasswordColumn` — or any column the schema marks secret — has **no field on the generated row**. It is not nullable, not empty: it is absent, and the generated file says so where the field would have been. The server strips it from responses, so a field for it could only ever hold null.

### An enum column gets its own type

A schema declaring `EnumColumn<Shelf>` generates `final BooksShelf shelf` — an extension type over `String`, with a named constant per declared member:

```dart no-analyze
if (book.shelf == BooksShelf.reading) { ... }

await client.books.list(where: Books.shelf.eq(BooksShelf.finished));
await client.books.update(
  where: Books.id.eq(book.id),
  set: BooksUpdate(shelf: Field.set(BooksShelf.finished)),
);
```

**Not a Dart `enum`, and that is the point.** A real enum makes a member the server adds later either a parse failure or a sentinel that loses the value. An extension type carries it regardless:

```dart no-analyze
// The server added `rescinded` after this client was generated.
print(book.shelf.value);      // 'rescinded' — nothing is lost
print(book.shelf.isKnown);    // false — and you can find out
```

The trade is that you do not get an exhaustive `switch`. `BooksShelf.values` lists what the schema declared at generation time, and `isKnown` is how you detect anything beyond it.

The name is table-qualified (`BooksShelf`, not `Shelf`) because two tables may each declare a `shelf` whose members differ, and because the generated client lives in the app's package and cannot import your server's `Shelf`. It erases to `String` at runtime, so the wire is exactly the member name.

`$.enumList` becomes `List<BooksTags>` under the same rules. `$.list` still becomes `List<Object?>` — the element type is not carried in the schema shape, so there is nothing to name.

## Typed ids

`PostsId` is an extension type over `String`, so it erases at runtime: it survives `jsonEncode` and `SendPort.send` untouched and needs no custom encoder. What it buys you is at compile time — passing an `AuthorsId` where a `PostsId` belongs stops compiling.

```dart no-analyze
final post = await client.posts.get(PostsId('abc123'));
```

Reach for the underlying string with `.value` when you need it in a `Where` clause.

## Expanded relations

A row that points at another table gets an `expanded` companion, populated only when the call asked for it:

```dart no-analyze
final post = await client.posts.get(postId, expand: [Posts.expand.authorId]);
print(post.expanded?.authorId?.name);
```

`expand` takes **typed paths**, built by chaining from `Posts.expand`. Each hop is typed by the table it points at, so a wrong turn stops compiling:

```dart no-analyze
final posts = await client.posts.list(
  expand: [
    Posts.expand.authorId,             // → 'author_id'
    Posts.expand.authorId.companyId,   // → 'author_id.company_id'
  ],
);
final company = posts.items.first.expanded?.authorId?.expanded?.companyId;
```

`Posts.expand.authorId.title` does not exist — `title` is a column, not a relation. The value on the wire is the same dotted string the untyped client takes, so nothing about the request changes.

Both sides are keyed by the **foreign-key column name**, not by a relation alias: you ask for `author_id` and you read `expanded?.authorId`. An unexpanded row is not an error; `expanded` is simply null.

The server caps depth at 4 and answers a deeper path with `ColumnNotExpandableException`. That cap is not enforced by the type system — a self-referencing key (`users.manager_id → users.id`) can be chained forever — so it is a debug assert on the client and the server's rejection in production.

## Acting as a user

Every generated method takes an optional `as:`, which sets the `Authorization` header:

```dart no-analyze
final page = await client.posts.list(as: Authorization.bearer(token));
```

`Authorization.bearer` adds the `Bearer ` prefix the server requires, so the header cannot be built wrong. Use `Authorization.raw` only when you already hold a complete header value.

<Warning>

**Types say nothing about permission.** `canView` / `canList` / `canUpdate` are evaluated on the server and still reject at runtime. A method existing in the generated client means the *shape* is known — not that this caller may call it. See [Rules](/rules/overview).

</Warning>

## Creating, updating and deleting

`create` takes a plain builder — there is no absent/NULL ambiguity on insert, so nothing is wrapped:

```dart no-analyze
final post = await client.posts.create(
  PostsCreate(authorId: author.id, title: 'Hello'),
);
```

The id is optional: the server generates one when you leave it out. Read-only columns — `created_at`, `updated_at`, anything server-generated — have no field at all.

`update` is different, and the difference is the point:

```dart no-analyze
// Set a value.
await client.posts.update(
  where: Posts.id.eq(post.id),
  set: PostsUpdate(title: Field.set('New title')),
);

// Set it to NULL — a distinct operation, and not expressible with a
// nullable named argument, because `null` there means "leave alone".
await client.posts.update(
  where: Posts.id.eq(post.id),
  set: const PostsUpdate(body: Field.clear()),
);
```

Each field takes a `Patch`, and which `Patch` depends on the column's kind — so the operations you can reach are the ones the column actually supports:

| Column kind | Patch | Beyond `set` / `clear` |
|-------------|-------|------------------------|
| anything | `Field` | — |
| `integer`, `real` | `NumField` | `increment`, `decrement`, `add`, `subtract` |
| `list`, `enumList`, `photos` | `ListField` | `add`, `remove`, `addAll`, `removeAll` |
| `map` | `MapField` | — |

```dart no-analyze
await client.articles.update(
  where: Articles.id.eq(id),
  set: const ArticlesUpdate(viewCount: NumField.increment()),
);
await client.articles.update(
  where: Articles.id.eq(id),
  set: ArticlesUpdate(tags: ListField.add('dart')),
);
```

`createMany`, `updateMany`, `delete` and `deleteMany` round out the set. Every one takes an optional `as`, like every read.

### Three ways the write side differs from the read side

- **A secret column is writable.** It is stripped from every *response*, so it has no field on the row — but you must be able to set a password, so `PostsCreate` and `PostsUpdate` do carry it.
- **A photo column inverts.** The row reads `Uri`; create and update take a `PhotoId`, which is what the server validates against.
- **`bigInt` has no write field**, for the same reason it has no column token: `Literal.toJson` runs `jsonEncode`, which rejects a `BigInt`, so the request would throw before it was sent.

A `DateTime` is converted to epoch milliseconds for you. The filter path already normalized it; the write path does not, and a raw `DateTime` in a create body throws — which is exactly the kind of encoding a generated client exists to absorb.

## Live queries

Every table's api carries a `listen` mirror of `get` / `list` / `count`:

```dart no-analyze
final stream = client.posts.listen.list(
  where: Posts.authorId.eq(author.id),
  orderBy: [Posts.createdAt.desc],
);
final subscription = stream.listen((posts) => setState(() => _posts = posts));
```

It takes the same tokens and the same typed expand paths as the non-streaming
methods, and it is the same subscription `client.db.listen` opens — only the rows
coming out of it are typed.

One asymmetry worth knowing: `listen.list` yields `Stream<List<PostsRow>>`, **not**
`Stream<Paginated<PostsRow>>`. The streaming endpoint carries no page metadata, so
mirroring the non-streaming return type would be a nicer symmetry and a lie.

`where` is required on `listen.one` and `listen.count`, and optional on `listen.list`
— matching what the server's stream bodies require.

## Views

A read-only view generates the same `Row` and `Api` types as a table, but **no write surface at all** — no `Create`, no `Update`, and none of the six mutations. The server has nothing to write through. `post_summary` becomes `client.postSummary`, documented in the generated source as *a read-only view*.

## Filtering and ordering by column token

`Posts` holds one token per column, and each token knows its own Dart type. That is
what decides which operators you can reach:

```dart no-analyze
final recent = await client.posts.list(
  where: And([
    Posts.authorId.eq(author.id),
    Posts.createdAt.gt(DateTime.now().subtract(const Duration(days: 7))),
    Posts.title.contains('release'),
  ]),
  orderBy: [Posts.createdAt.desc],
);
```

Nothing on the wire changes — every token returns the same `Where` and `OrderByTerm`
the untyped client already takes. What changes is what stops compiling:

| Expression | Result |
|------------|--------|
| `Posts.title.contains('x')` | compiles — `title` is text |
| `Posts.createdAt.contains('x')` | **does not compile** — `contains` is only on `ColumnRef<String>` |
| `Posts.createdAt.gt(aDateTime)` | compiles, and sends epoch milliseconds |
| `Posts.body.isNull` | compiles — `body` is nullable |
| `Posts.title.isNull` | **does not compile** — `isNull` is only on a nullable column |
| `Posts.authorId.eq(somePostsId)` | **does not compile** — `author_id` is an `AuthorsId` |

`groupBy` takes a token too:

```dart no-analyze
final byAuthor = await client.posts.list(groupBy: Posts.authorId);
```

### Which columns get a token

A token is a promise that if the call compiles, the filter works. Columns where that
promise cannot be kept get **no token at all**, because a filter that looks
type-checked and silently matches nothing is worse than no help:

| Column kind | Why there is no token |
|-------------|----------------------|
| secret | Stripped from every response, and the server rejects it in a filter |
| photo | Stores a photo **id** but reads back a URL, so filtering by the URL you read would match nothing |
| `list`, `enumList`, `map`, blob | Stored as a JSON-encoded string; a filter built from the decoded value never matches |
| `bigInt` | `BigInt` is not JSON-encodable, so the request throws before it is sent |

You can still filter those columns through `client.db.list` with a hand-built `Where`,
where the encoding is visibly your problem.

## Where the query vocabulary comes from

`Where`, `Update`, `OrderByTerm`, `SortDirection`, `Eq`, `Gt`, `In`, `Contains` and the rest are exported by `zonai_client`, and the generated barrel re-exports them. One import is enough to name any of them — including `Paginated`, which `list` returns:

```dart no-analyze
import 'package:my_app/gen/zonai/zonai_client.g.dart';
```

### When a table name collides

`zonai_client` exports 71 names, and a table can generate one of them — a table named `photos` produces a `Photos` token holder, and `zonai_client` has a `Photos` of its own. Exporting both would be an ambiguous export, so the generated barrel hides the package's version and says so in the file:

```dart no-analyze
/// `Photos` is hidden: `photos` generates a type of that name, and exporting
/// both would be an ambiguous export.
export 'package:zonai_client/zonai_client.dart' hide Photos;
```

The name you get from the barrel is **yours** — the generated one. Nothing is refused and nothing else is affected. To reach `zonai_client`'s version, import that package with a prefix, or rename the generated class with [`client.names.<table>.row`](/configuration/zonai-yaml#client-settings) and the hide clause disappears with it.

If you have a colliding table and you still import `package:zonai_client/zonai_client.dart` directly, **drop that import** — that is the fix, not a workaround. The `hide` clause only governs what the generated barrel re-exports; two explicit imports both offering `Photos` is an ambiguous *import*, in your library, which the generator cannot reach. That ambiguity is not new — a colliding table name does it today, with or without the re-export — and dropping the second import is what makes it go away, because the only `Photos` left in scope is yours.

Most schemas collide with nothing and the clause is absent entirely.

Two members are deliberately **not** exported: `Null` and `NotNull`. A library importing them would shadow `dart:core`'s `Null` — Dart resolves an explicit import ahead of the implicit `dart:core` one, so every `Null` written in that library would mean the where-clause class instead. Build those clauses with the factories:

```dart no-analyze
final drafts = await client.posts.list(where: Where.isNull('published_at'));
final live = await client.posts.list(where: Where.isNotNull('published_at'));
```

The column tokens above already do this for you — `Posts.publishedAt.isNull` builds the
same clause without either name being in scope.

## Keeping it in sync

The generated client is a build artifact of your schema. After changing a table, re-run `zonai gen client` and commit the result; `zonai gen client --check` fails when the committed copy has gone stale. See [`zonai gen`](/cli/gen#keeping-the-committed-client-honest).

## See Also

- [`zonai gen`](/cli/gen) — the command and its flags
- [`client:` configuration](/configuration/zonai-yaml#client-settings)
- [Dart Client Overview](/dart-client/overview) — installation and `baseUrl`
- [Streaming (Live Queries)](/operations/streaming) — the untyped `client.db.listen` and how streaming works
