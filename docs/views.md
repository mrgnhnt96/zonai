# Views

A **view** is a read-only collection defined by a query instead of a real SQLite table — typically a join or projection across other collections. Views are exposed through the same `/db` surface as regular collections and go through the same [rules](rules.md) checks; they just have no `INSERT`/`UPDATE`/`DELETE` path, ever.

Views are a `zonai_schema`-only concept. There is no `CREATE VIEW` in the generated SQLite migrations, no Raindrop schema change, and no new `zonai.yaml` path — a view is one operations file plus a pair of rules files, wired together like any other collection except the operations file also defines the row shape, and builds its query with a `ViewQuery` instead of default CRUD.

## How it works

1. In an operations file (under `operationsPath`), you declare a normal-looking schema (`table(...)`) for the view's row shape, right alongside the query that produces it — never under `schemasPath`, so the migration generator can't discover it as a real table.
2. You implement `ViewQuery<R>` with two methods, `query()` and `countQuery()`, using Raindrop's own `.select(...).from(...).join(...)` builder to describe the join. Every selected column is aliased with `.aliasedAs(...)` to match the view schema's column names exactly.
3. The same file's `main()` returns `ViewOperations(viewSchema, YourViewQuery())` — a `final` class you compose with, not extend.
4. `ViewOperations` applies `where`/`limit`/`offset`/`orderBy` on top of your query the same way default `list()` does for a regular table, and rejects every write operation and every rules bypass with `UnsupportedError`.
5. You write `ViewTableRules`/`ViewRowRules` (extending the regular `TableRules`/`RowRules` base classes) to control read access — `canCreate`/`canUpdate`/`canDelete` are already hard-denied by the base view rules classes, admin token or not.

## Why the schema lives in the operations file

Every other collection's schema is discoverable by two independent scanners: raindrop_cli's migration generator (`--schemas schemasPath`, type-based — it finds *any* top-level variable whose static type extends raindrop's `Schema`, regardless of what function produced it) and zonai's own tooling that scans `schemasPath` for `table(...)`/`authTable(...)` calls. Both only ever look inside `schemasPath`.

A view's schema needs the exact same `Table<R>` machinery — that's what gives rules a typed `R` to check via `Table.safeCreate`/`fromRow` — but it must never be found by either scanner, or `dart run zonai compile`/`serve` would try to generate a real `CREATE TABLE` migration for a query that has no backing table. Putting it in its own directory (e.g. a hypothetical `lib/src/views/`) only prevents that by convention — nothing stops it from being moved into `schemasPath` by mistake, since raindrop_cli's discovery doesn't care what the enclosing function or file is named.

Defining it inside the operations file sidesteps that risk structurally instead of by convention: `operationsPath` is never passed to raindrop_cli and is never scanned for migrations, so the schema is safe by construction, not by discipline. It also means the "shape" (columns) and the "mapping" (which source column feeds which column, via which join) live in one file, making the fact that they must stay in sync visually obvious.

## Writing the view

Both the schema and `ViewQuery<R>` live in one operations file. Import only `zonai_schema` — it re-exports raindrop's query builder (`.select`/`.from`/`.join`, `count`, etc.) already, so a separate `package:raindrop/raindrop.dart` import isn't needed and will collide: both packages would then export symbols like `Table`/`table`, producing `ambiguous_import`.

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

The schema half is an ordinary `Table<R>` — `Table.safeCreate`/`fromRow` reconstruct rows from raw SQL result maps exactly like a regular collection, which is how rules get a typed `R` to check against.

`ViewQuery` is `abstract base class` — subclass it with `final class` (or `base class` if you need a further subclass of your own). Rules to follow for `query()`/`countQuery()`:

- **Must not call `.where`/`.limit`/`.offset`/`.orderBy`.** `ViewOperations` applies those on top for every request; a view can't opt out.
- **`countQuery()` mirrors the same joins as `query()`**, projecting a countable expression (`count(...)`) instead of the column list — the same relationship a regular table's `count()` has to its `list()`.
- **Alias every selected column with `.aliasedAs(name)`, matching the view schema's declared column name exactly** (`authors.name.aliasedAs('author_name')`, not `authors.name`). Raindrop auto-qualifies and auto-aliases every projected column as `"table__column"` the moment a query has a join — without `.aliasedAs`, the raw SQL result won't have a column named `author_name` at all, and `Table.safeCreate` won't be able to reconstruct a row.

### Filtering caveat

A caller's `where` and `orderBy` reference columns by the name `query()` selects them as. `ORDER BY` can reference a `.select` alias; `WHERE` generally cannot in standard SQL, since it's evaluated before the `SELECT` list. Expose a column under its natural, unambiguous source-table name if you need it filterable — not a renamed alias that only makes sense in the projection.

The same applies to the default sort when no `orderBy` is given: it falls back to an unqualified reference (`"column"`, no table prefix), because the view has no real `FROM`/`JOIN` target to qualify with. If two joined tables share a column name that ends up in the default-sort candidate list (commonly `id`), that reference is ambiguous — pass an explicit `orderBy` (or `orderBy: []` to opt out of the default entirely) rather than relying on the fallback.

## Writing the rules

`ViewTableRules`/`ViewRowRules` extend the regular `TableRules`/`RowRules` base classes and hard-deny `canCreate`/`canUpdate`/`canDelete` — including for admin tokens, which the regular base classes grant by default. Only `canView`/`canList` (table) and `canView` (row) are yours to override. Import the schema from the operations file that declares it:

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

These go under `rulesPath` exactly like any other collection's rules files — one collection-rules file and one row-rules file, keyed by the view's table name (`post_summary`).

Write access is denied twice over: the rules layer above denies it before SQL is ever built, and `ViewOperations` itself throws `UnsupportedError` from `insert`/`insertMany`/`update`/`delete` if somehow reached anyway. In practice, a request hits the rules denial first — `POST`/`PATCH`/`DELETE` against a view return a plain `403`, the same as any other rules rejection.

## What you can't override

`ViewOperations` is `final` — you construct it, you don't extend it. This is deliberate: the class that applies `where`/`limit`/`offset`/`orderBy` on top of your query is the same class that must guarantee every read goes through that logic and every write is rejected, and neither guarantee holds if a subclass can override `list()`/`count()`/`insert()`/etc. to bypass it. `list()` and `count()` themselves are overridden to throw `UnsupportedError` pointing at the real entry points — `compileList`/`compileCount` — which are the ones the framework actually calls for `GET /db/list`, `GET /db`, and `GET /db/count` requests against a view.

The only thing you write for a view is the schema, `ViewQuery`'s two methods, and the two rules files. Everything else — pagination, filtering, sort, write rejection, rules enforcement — is handled once, centrally, for every view.

## Project layout

```text
lib/src/operations/
  post_summary_operations.dart   # schema + ViewOperations + ViewQuery, all in one file

lib/src/rules/
  post_summary_table_rules.dart
  post_summary_row_rules.dart
```

Nothing for a view goes under `schemasPath`.

## Configuration

No new `zonai.yaml` keys:

```yaml
schemasPath: lib/src/schemas       # scanned for migrations — a view's schema must never be here
operationsPath: lib/src/operations # a view's schema + query both live here
rulesPath: lib/src/rules           # views need rules files here too
```

## Minimal example

From the playground app — `post_summary` projects each post's title next to its author's name:

- Schema + query: `apps/playground/lib/src/operations/post_summary_operations.dart`
- Rules: `apps/playground/lib/src/rules/post_summary_table_rules.dart`, `post_summary_row_rules.dart`

```bash
curl -G 'localhost:8080/db/list' --data-urlencode 'body={"table":"post_summary"}'
```

returns joined rows (`id`, `title`, `author_name`) filtered, sorted, and paginated exactly like a regular collection's `list` endpoint — while `POST`/`PATCH`/`DELETE` against the same table all return `403`.

## See also

- **[rules.md](rules.md)** — collection and record access rules (checked before SQL runs)
- **[operations.md](operations.md)** — how regular collections turn requests into SQL
- **`libs/zonai_schema/lib/src/operations/view_operations.dart`** — full implementation of `ViewQuery`/`ViewOperations`
