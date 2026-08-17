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
import 'package:zonai_client/zonai_client.dart';
import 'package:my_app/gen/zonai/zonai_client.g.dart';

final typed = await client.posts.list();
final raw = await client.db.list(
  body: ListBody(table: 'posts'),
  fromJson: (row) => row,
);
```

You keep `client.auth`, `client.photos`, `client.email` and `client.db.listen` exactly as they were.

<Warning>

**Phase 1 generates read operations only** — `get`, `list` and `count`. Creates, updates and deletes still go through `client.db`, and so do live streams (`client.db.listen`). A table's generated API having no `create` method does not mean the table is read-only.

</Warning>

## What is generated per table

For a table `posts` you get four names, all derived from one stem:

| Name | What it is |
|------|-----------|
| `PostsRow` | One decoded row — `String`, `DateTime`, `bool`, lists and maps, not raw storage |
| `PostsId` | An extension type over `String` for that table's id |
| `PostsApi` | `get` / `list` / `count` for the table |
| `client.posts` | The accessor, added by an extension on `ZonaiClient` |

Rename all four at once with [`names.<table>.row`](/configuration/zonai-yaml#client-settings) — an override that moved one name out of four would be no escape hatch at all for the case that most needs one, a table name that is not a usable Dart identifier.

## Typed ids

`PostsId` is an extension type over `String`, so it erases at runtime: it survives `jsonEncode` and `SendPort.send` untouched and needs no custom encoder. What it buys you is at compile time — passing an `AuthorsId` where a `PostsId` belongs stops compiling.

```dart no-analyze
final post = await client.posts.get(PostsId('abc123'));
```

Reach for the underlying string with `.value` when you need it in a `Where` clause.

## Expanded relations

A row that points at another table gets an `expanded` companion, populated only when the call asked for it:

```dart no-analyze
final post = await client.posts.get(postId, expand: ['author_id']);
print(post.expanded?.author?.name);
```

`expand` takes the wire paths the server understands — `['author_id', 'author_id.company_id']`, dotted, capped at depth 4. An unexpanded row is not an error; `expanded` is simply null.

## Acting as a user

Every generated method takes an optional `as:`, which sets the `Authorization` header:

```dart no-analyze
final page = await client.posts.list(as: Authorization.bearer(token));
```

`Authorization.bearer` adds the `Bearer ` prefix the server requires, so the header cannot be built wrong. Use `Authorization.raw` only when you already hold a complete header value.

<Warning>

**Types say nothing about permission.** `canView` / `canList` / `canUpdate` are evaluated on the server and still reject at runtime. A method existing in the generated client means the *shape* is known — not that this caller may call it. See [Rules](/rules/overview).

</Warning>

## Views

A read-only view generates the same `Row` and `Api` types as a table. `post_summary` becomes `client.postSummary`, documented in the generated source as *a read-only view*.

## Where the query vocabulary comes from

`Where`, `Update`, `OrderByTerm`, `SortDirection`, `Eq`, `Gt`, `In`, `Contains` and the rest are exported by `zonai_client` itself, so importing the generated client is enough to name them.

Two members are deliberately **not** exported: `Null` and `NotNull`. A library importing them would shadow `dart:core`'s `Null` — Dart resolves an explicit import ahead of the implicit `dart:core` one, so every `Null` written in that library would mean the where-clause class instead. Build those clauses with the factories:

```dart no-analyze
final drafts = await client.posts.list(where: Where.isNull('published_at'));
final live = await client.posts.list(where: Where.isNotNull('published_at'));
```

## Keeping it in sync

The generated client is a build artifact of your schema. After changing a table, re-run `zonai gen client` and commit the result; `zonai gen client --check` fails when the committed copy has gone stale. See [`zonai gen`](/cli/gen#keeping-the-committed-client-honest).

## See Also

- [`zonai gen`](/cli/gen) — the command and its flags
- [`client:` configuration](/configuration/zonai-yaml#client-settings)
- [Dart Client Overview](/dart-client/overview) — installation and `baseUrl`
- [Streaming (Live Queries)](/operations/streaming) — still `client.db.listen`
