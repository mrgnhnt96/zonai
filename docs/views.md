# Views

A **view** is a read-only collection defined by a query instead of a real SQLite table — typically a join or projection across other collections. Views are exposed through the same `/db` surface as regular collections and go through the same [rules](rules.md) checks; they just have no `INSERT`/`UPDATE`/`DELETE` path, ever.

Views are a `zonai_schema`-only concept. There is no `CREATE VIEW` in the generated SQLite migrations, no Raindrop schema change, and no new `zonai.yaml` path — a view is a schema, an operations file, and a pair of rules files, wired together like any other collection except the schema lives outside `schemasPath` and the operations file builds its query with a `ViewQuery` instead of default CRUD.

## How it works

1. You declare a normal-looking schema (`table(...)`) for the view's row shape, but in a file the migration generator never scans — it has no backing SQLite table, so it must never be discovered as one.
2. You implement `ViewQuery<R>` with two methods, `query()` and `countQuery()`, using Raindrop's own `.select(...).from(...).join(...)` builder to describe the join. Every selected column is aliased with `.aliasedAs(...)` to match the view schema's column names exactly.
3. Your operations file's `main()` returns `ViewOperations(viewSchema, YourViewQuery())` — a `final` class you compose with, not extend.
4. `ViewOperations` applies `where`/`limit`/`offset`/`orderBy` on top of your query the same way default `list()` does for a regular table, and rejects every write operation and every rules bypass with `UnsupportedError`.
5. You write `ViewTableRules`/`ViewRowRules` (extending the regular `TableRules`/`RowRules` base classes) to control read access — `canCreate`/`canUpdate`/`canDelete` are already hard-denied by the base view rules classes, admin token or not.

## Defining the schema

Put the view's schema next to your other domain code, but **outside `schemasPath`** — for example `lib/src/views/post_summary.dart` rather than `lib/src/schemas/`:

```dart
import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

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
```

This is an ordinary `Table<R>` — `Table.safeCreate`/`fromRow` reconstruct rows from raw SQL result maps exactly like a regular collection, which is how rules get a typed `R` to check against. The only thing that makes it a view rather than a table is where it's registered (an operations file, via `ViewOperations`) and where it's *not* declared (`schemasPath`, so `dart run zonai compile`/`serve` never generates a migration for it).

## Writing the query

`ViewQuery<R>` is the only thing you implement — two methods, no `where`/`limit`/`offset`/`orderBy`:

```dart
import 'package:raindrop/raindrop.dart' hide Table;
import 'package:zonai_schema/zonai_schema.dart';

import '../schemas/authors.dart';
import '../schemas/posts.dart';
import '../views/post_summary.dart';

ViewOperations<PostSummary> main() =>
    ViewOperations(postSummary, PostSummaryQuery());

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

`ViewQuery` is `abstract base class` — subclass it with `final class` (or `base class` if you need a further subclass of your own).

Rules to follow:

- **`query()` and `countQuery()` must not call `.where`/`.limit`/`.offset`/`.orderBy`.** `ViewOperations` applies those on top for every request; a view can't opt out.
- **`countQuery()` mirrors the same joins as `query()`**, projecting a countable expression (`count(...)`) instead of the column list — the same relationship a regular table's `count()` has to its `list()`.
- **Alias every selected column with `.aliasedAs(name)`, matching the view schema's declared column name exactly** (`authors.name.aliasedAs('author_name')`, not `authors.name`). Raindrop auto-qualifies and auto-aliases every projected column as `"table__column"` the moment a query has a join — without `.aliasedAs`, the raw SQL result won't have a column named `author_name` at all, and `Table.safeCreate` won't be able to reconstruct a row.

### Filtering caveat

A caller's `where` and `orderBy` reference columns by the name `query()` selects them as. `ORDER BY` can reference a `.select` alias; `WHERE` generally cannot in standard SQL, since it's evaluated before the `SELECT` list. Expose a column under its natural, unambiguous source-table name if you need it filterable — not a renamed alias that only makes sense in the projection.

The same applies to the default sort when no `orderBy` is given: it falls back to an unqualified reference (`"column"`, no table prefix), because the view has no real `FROM`/`JOIN` target to qualify with. If two joined tables share a column name that ends up in the default-sort candidate list (commonly `id`), that reference is ambiguous — pass an explicit `orderBy` (or `orderBy: []` to opt out of the default entirely) rather than relying on the fallback.

## Writing the rules

`ViewTableRules`/`ViewRowRules` extend the regular `TableRules`/`RowRules` base classes and hard-deny `canCreate`/`canUpdate`/`canDelete` — including for admin tokens, which the regular base classes grant by default. Only `canView`/`canList` (table) and `canView` (row) are yours to override:

```dart
import 'package:zonai_schema/zonai_schema.dart';

import '../views/post_summary.dart';

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

import '../views/post_summary.dart';

PostSummaryRowRules main() => PostSummaryRowRules();

final class PostSummaryRowRules
    extends ViewRowRules<PostSummaryTable, PostSummary> {
  PostSummaryRowRules() : super(postSummary);

  @override
  Future<bool> canView(Jwt? jwt, PostSummary row) async => true;
}
```

These go under `rulesPath` exactly like any other collection's rules files — one collection-rules file and one row-rules file, keyed by the view's table name (`post_summary`).

Write access is denied twice over: the rules layer above denies it before SQL is ever built, and `ViewOperations` itself throws `UnsupportedError` from `insert`/`insertMany`/`update`/`delete` if somehow reached anyway. In practice, a request hits the rules denial first — `POST`/`PATCH`/`DELETE` against a view return a plain `403`, the same as any other rules rejection.

## What you can't override

`ViewOperations` is `final` — you construct it, you don't extend it. This is deliberate: the class that applies `where`/`limit`/`offset`/`orderBy` on top of your query is the same class that must guarantee every read goes through that logic and every write is rejected, and neither guarantee holds if a subclass can override `list()`/`count()`/`insert()`/etc. to bypass it. `list()` and `count()` themselves are overridden to throw `UnsupportedError` pointing at the real entry points — `compileList`/`compileCount` — which are the ones the framework actually calls for `GET /db/list`, `GET /db`, and `GET /db/count` requests against a view.

The only thing you write for a view is `ViewQuery`'s two methods and the two rules files. Everything else — pagination, filtering, sort, write rejection, rules enforcement — is handled once, centrally, for every view.

## Project layout

```text
lib/src/views/
  post_summary.dart              # schema — NOT under schemasPath

lib/src/operations/
  post_summary_operations.dart   # ViewOperations + ViewQuery

lib/src/rules/
  post_summary_table_rules.dart
  post_summary_row_rules.dart
```

## Configuration

No new `zonai.yaml` keys. A view's schema simply lives somewhere other than `schemasPath`, so the migration generator never sees it:

```yaml
schemasPath: lib/src/schemas       # scanned for migrations — views must stay out of this
operationsPath: lib/src/operations # views register here, alongside regular custom operations
rulesPath: lib/src/rules           # views need rules files here too
```

## Minimal example

From the playground app — `post_summary` projects each post's title next to its author's name:

- Schema: `apps/playground/lib/src/views/post_summary.dart`
- Query: `apps/playground/lib/src/operations/post_summary_operations.dart`
- Rules: `apps/playground/lib/src/rules/post_summary_table_rules.dart`, `post_summary_row_rules.dart`

```bash
curl 'localhost:8080/db/list?table=post_summary'
```

returns joined rows (`id`, `title`, `author_name`) filtered, sorted, and paginated exactly like a regular collection's `list` endpoint — while `POST`/`PATCH`/`DELETE` against the same table all return `403`.

## See also

- **[rules.md](rules.md)** — collection and record access rules (checked before SQL runs)
- **[operations.md](operations.md)** — how regular collections turn requests into SQL
- **`libs/zonai_schema/lib/src/operations/view_operations.dart`** — full implementation of `ViewQuery`/`ViewOperations`
