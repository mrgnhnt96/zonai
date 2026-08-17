---
title: Views (Read-Only Collections)
description: Expose a join or a projection over the same /db surface as a real table, with writes refused twice over.
---

A **view** is a collection defined by a query instead of a table — typically a join or a projection across collections you already have. It is served over the same `/db` surface as everything else and goes through the same [rules](/rules/overview), with one difference that never varies: **there is no write path, ever.**

| Request | A view |
|---|---|
| `GET /db`, `GET /db/list`, `GET /db/count` | Filtered, sorted and paginated exactly like a real collection. |
| `POST`, `PATCH`, `DELETE /db` | `403`, from the rules layer, before any SQL is built. |

Views are a `zonai_schema` concept and nothing else. There is no `CREATE VIEW` in your migrations, no schema change, and no new `zonai.yaml` key — a view is **one operations file plus two rules files**.

## The schema lives in the operations file

This is the part that looks wrong until you know why, so it comes first: a view's `table(...)` declaration goes under `operationsPath`, **never** under `schemasPath`.

A view needs the full `Table<R>` machinery, because that is what gives rules a typed row to check and what reconstructs rows from raw SQL results. But two independent scanners look for exactly that shape, and both only ever look inside `schemasPath`:

- raindrop's migration generator, which finds *any* top-level variable whose static type extends `Schema` — regardless of what function produced it;
- Zonai's own tooling, which scans for `table(...)` / `authTable(...)` calls.

If either found a view, `zonai compile` would try to generate a `CREATE TABLE` for a query with no backing table. `operationsPath` is never handed to the migration generator and never scanned for schemas, so putting the declaration there makes that impossible **by construction** rather than by convention. A separate `views/` directory would only prevent it by everyone remembering.

It has a second payoff: the shape (which columns exist) and the mapping (which source column feeds each one, through which join) sit in one file, where the fact that they must agree is visible.

## Writing the view

Import only `zonai_schema` — it already re-exports raindrop's query builder (`.select`, `.from`, `.join`, `count`). Adding `package:raindrop/raindrop.dart` alongside it produces `ambiguous_import`, because both packages export `Table` and `table`.

```dart
import 'package:my_app/src/ids.dart';
import 'package:my_app/src/schemas/authors.dart';
import 'package:my_app/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

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
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: PostsId.new,
        generate: PostsId.generate,
      ),
      title = $.text('title', (s) => s.title),
      authorName = $.text('author_name', (s) => s.authorName);

  @override
  PostSummary fromRow(RowReader read) => PostSummary(
    id: read(id),
    title: read(title)!,
    authorName: read(authorName)!,
  );

  final IdColumn<PostsId> id;
  final TextColumn title;
  final TextColumn authorName;
}

final postSummary = table('post_summary', PostSummaryTable.new);

final class PostSummaryQuery extends ViewQuery<PostSummary> {
  @override
  SelectFromBuilder<dynamic, dynamic, dynamic> query() {
    return db
        .select(
          posts.id.aliasedAs('id'),
          posts.title.aliasedAs('title'),
          authors.name.aliasedAs('author_name'),
        )
        .from(posts)
        .join(authors, on: posts.authorId.equals(authors.id));
  }

  @override
  SelectFromBuilder<dynamic, dynamic, dynamic> countQuery() {
    return db
        .select(count(posts.id))
        .from(posts)
        .join(authors, on: posts.authorId.equals(authors.id));
  }
}
```

`main()` returns a `ViewOperations` you **compose** — the schema and the query, handed to a `final` class.

`ViewQuery` is an `abstract base class`, so subclass it with `final class` (or `base class` if you need your own subclass beneath it).

### Three rules for `query()` and `countQuery()`

**Alias every selected column with `.aliasedAs(...)`, matching the view schema's column name exactly.** Not optional and not cosmetic: the moment a query has a join, raindrop auto-qualifies every projected column as `"table__column"`. Without `.aliasedAs('author_name')` there is no `author_name` in the result at all, and the row cannot be reconstructed.

**Never call `.where`, `.limit`, `.offset` or `.orderBy`.** `ViewOperations` applies those on top of your query for every request, the same way `list()` does for a real collection. A view does not get to opt out of them.

**`countQuery()` must mirror `query()`'s joins**, projecting `count(...)` instead of the column list — the same relationship a table's `count()` has to its `list()`. Joins that disagree make a count that does not describe the list.

### Filtering and sorting have a sharp edge

A caller's `where` and `orderBy` name columns as your `query()` selects them. `ORDER BY` can refer to a `SELECT` alias; **`WHERE` generally cannot**, because it is evaluated before the projection. So a column that callers need to filter on should be exposed under its natural source name, not a renamed alias that only makes sense in the output.

The default sort has a related trap. With no `orderBy`, the fallback is an unqualified column reference — no table prefix — because a view has no single `FROM` target to qualify against. If two joined tables share a column name that lands in the default-sort candidates (`id`, most often), that reference is ambiguous and the query fails. Pass an explicit `orderBy`, or `orderBy: []` to opt out of the default entirely, rather than relying on the fallback.

## Writing the rules

Two files under `rulesPath`, keyed by the view's table name, exactly like any other collection. They extend `ViewTableRules` / `ViewRowRules`, which **hard-deny `canCreate`, `canUpdate` and `canDelete` — including for an admin token**, which the ordinary base classes grant by default. Only reads are yours to decide.

```dart
import 'package:zonai_schema/zonai_schema.dart';

import '../operations/post_summary_operations.dart';

PostSummaryTableRules main() => PostSummaryTableRules();

final class PostSummaryTableRules
    extends ViewTableRules<PostSummaryTable, PostSummary> {
  PostSummaryTableRules() : super(postSummary);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;
}
```

```dart
import 'package:zonai_schema/zonai_schema.dart';

import '../operations/post_summary_operations.dart';

PostSummaryRowRules main() => PostSummaryRowRules();

final class PostSummaryRowRules
    extends ViewRowRules<PostSummaryTable, PostSummary> {
  PostSummaryRowRules() : super(postSummary);

  @override
  Future<bool> canView(Jwt? jwt, PostSummary row) async => true;
}
```

The schema is imported from the operations file that declares it — the one place it exists.

**Write access is denied twice.** Rules refuse it before any SQL is built, and `ViewOperations` itself throws `UnsupportedError` from `insert` / `insertMany` / `update` / `delete` if something ever reached them. In practice a request meets the rules denial first and gets a plain `403`, indistinguishable from any other rules rejection — the second layer exists for the path no request takes.

## What you cannot override

`ViewOperations` is `final`. You construct it; you do not extend it.

That is the same guarantee stated in the type system: the class that layers `where`/`limit`/`offset`/`orderBy` onto your query is also the class that must ensure every read goes through that logic and every write is refused. Neither survives a subclass overriding `list()` or `insert()`. `list()` and `count()` are themselves overridden to throw, pointing at `compileList` / `compileCount` — the entry points the framework actually calls for `GET /db`, `GET /db/list` and `GET /db/count` against a view.

So everything you write for a view is: the schema, two `ViewQuery` methods, and two rules files. Pagination, filtering, sort, write rejection and rules enforcement are handled once, centrally, for every view.

## Layout

```text
lib/src/operations/
  post_summary_operations.dart   # schema + ViewOperations + ViewQuery, one file

lib/src/rules/
  post_summary_table_rules.dart
  post_summary_row_rules.dart
```

Nothing for a view goes under `schemasPath`. No `zonai.yaml` key changes:

```yaml
schemasPath: lib/src/schemas       # scanned for migrations — a view must never be here
operationsPath: lib/src/operations # the view's schema and query both live here
rulesPath: lib/src/rules           # its two rules files
```

## Reading it

```bash
curl -G 'localhost:8080/db/list' --data-urlencode 'body={"table":"post_summary"}'
```

Joined rows — `id`, `title`, `author_name` — filtered, sorted and paginated like any collection's list endpoint, while `POST`, `PATCH` and `DELETE` against `post_summary` all return `403`.

## Related

- **[Default Operations](/operations/default-operations)** — the request and response shapes a view answers with.
- **[Rules Overview](/rules/overview)** — the deny-by-default model these rules classes plug into.
- **[Defining Tables](/schemas/defining-tables)** — the `Table<R>` machinery a view's schema reuses.
