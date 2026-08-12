# Paying off the doc-snippet drift backlog (#26)

Handoff doc. The compile check for the docs' `dart` examples already exists and
is green; this is the list of examples it had to excuse to get there, grouped by
root cause, with the real API for each.

## What already landed

`fe56393` added `apps/playground/test/doc_snippets_test.dart`. It pulls every
fenced ` ```dart ` example out of `docs/*.md`, `apps/docs/content/**/*.md` and
`apps/zonai/lib/src/commands/ai/ai_templates.dart`, keeps the 67 that are
self-contained files, and runs `dart analyze` over them.

- Snippets are written under `apps/playground/lib/src/__doc_snippets__/`
  (deleted afterwards) because the examples use the relative imports of a real
  zonai project — `../ids.dart`, `../schemas/items.dart` — which only resolve
  from inside one.
- `package:my_app/src/schemas/X.dart` is the docs' stand-in for the reader's own
  project. The test rewrites it to the playground's table where one exists
  (`users`, `items`, `posts`, `authors`, `companies`) and to
  `apps/playground/test/fixtures/doc_snippets/X.dart` otherwise (`tasks`,
  `profiles`, `articles`).
- 26 snippets don't analyze. They're listed in
  `apps/playground/test/doc_snippets_baseline.txt`, keyed by `<source>#<hash of
  the snippet body>`.

The test fails if a snippet outside the baseline breaks, **and** if a baseline
line stops excusing anything — either because the snippet now compiles or
because it was edited and no longer has that key. So the list can only shrink.

## The loop

```
cd apps/playground && dart test test/doc_snippets_test.dart
```

Takes ~1s after the first analyze. For each item:

1. Fix the example in the markdown (or in `ai_templates.dart`).
2. Run the test. It will now fail saying the old baseline key
   `(no such snippet)` — that is the expected signal, not a problem.
3. Delete that line from `doc_snippets_baseline.txt`.
4. Run again; green.

Do **not** re-add a new key for the edited snippet unless it still legitimately
can't compile — and if you do, say why on the line above it.

`docs/*.md`, `apps/docs/content/**` and `ai_templates.dart` all have verify
rules pointing at this test, so a commit touching them runs it.

### Two traps

- **Editing `apps/docs/content/**` means regenerating the search index**:
  `sip run docs index`, or `apps/docs`'s own tests fail on a stale one.
- **The AI templates are duplicated.** Several snippets appear twice in
  `ai_templates.dart` (e.g. at `:425` and `:1314`). They share one baseline key,
  so **both copies must be fixed** before the line can go — fixing one changes
  its hash while the other keeps failing under the old key.

---

## The backlog, by root cause

### 1. `extends Id` — 4 snippets, highest impact

`quick-start.md:40`, `quick-start.md:90`, `schemas/defining-tables.md:75`,
`schemas/auth-tables.md:89`

```
INVALID_USE_OF_TYPE_OUTSIDE_LIBRARY: The class 'Id' can't be extended outside
of its library because it's an interface class.
```

The docs tell readers to write `class UsersId extends Id { const UsersId(super.value); }`.
`zonai_schema`'s `Id` is an `abstract interface class` (`libs/zonai_schema/lib/src/types/id.dart:6`)
with no field to inherit, so that has never compiled.

The pattern the playground actually uses (`apps/playground/lib/src/ids.dart`) is
a *local* sealed base that implements it, with per-table subclasses off that:

```dart
import 'package:zonai_schema/zonai_schema.dart' as z;

sealed class Id implements z.Id {
  const Id(this.value);
  @override
  final String value;
  // == / hashCode / toString
}

class UsersId extends Id {
  const UsersId(super.value);
  factory UsersId.generate() => UsersId(z.Id.generate(_suffix));
  static const _suffix = 'us';
}
```

Decide which one the docs should teach — the local sealed base (matches the
playground and the `ids.dart` the docs already reference elsewhere) or a bare
`implements z.Id` per table — then apply it to all four consistently. This is
the first thing a new user copies, so it's worth getting right rather than
minimally green.

### 2. Column type names that don't exist — 4 snippets

`quick-start.md:40`, `quick-start.md:90`, `defining-tables.md:75`,
`auth-tables.md:89`

```
UNDEFINED_CLASS: Undefined class 'CreatedAtColumn' / 'UpdatedAtColumn'
                                 / 'IntegerColumn'  / 'BoolColumn'
```

The exported column types are `TextColumn`, `DateTimeColumn`, `IdColumn`,
`BooleanColumn`, `IntColumn`. There is no `CreatedAtColumn`, `UpdatedAtColumn`,
`IntegerColumn` or `BoolColumn` — the builders `$.createdAt(...)` /
`$.updatedAt(...)` exist, but their fields are typed `DateTimeColumn` and
`ColumnType<DateTime?>`. See `apps/playground/lib/src/schemas/items.dart` for a
table that declares all of these correctly.

Nullable columns are `ColumnType<T?>`, which also fixes the neighbouring
`RETURN_OF_INVALID_TYPE_FROM_CLOSURE: 'DateTime?' isn't returnable from a
'DateTime' function` and `UNDEFINED_NAMED_PARAMETER: 'isNullable'`.

### 3. Extensions — 4 snippets

`extensions/auth-hooks.md:10`, `docs/extensions.md:64`, `docs/extensions.md:228`,
`ai_templates.dart:454` / `:1388`

Ground truth is `libs/zonai_schema/lib/src/extension.dart`:

- `abstract class Extension<T>` with a **positional** schema:
  `Extension(this.schema)`.
- `mixin AuthExtension<R> on Extension<R>` — **one** type parameter, and it is a
  mixin, so `class UserExtensions extends Extension<User> with AuthExtension<User>`.
  The docs write `with AuthExtension<UserTable, User>` (two args) and in places
  `with Extension<...>`, which is why `MIXIN_OF_NON_CLASS` and
  `WRONG_NUMBER_OF_TYPE_ARGUMENTS` fire.
- Hook signatures all take a trailing `Jwt? jwt`: `onSignUp(R user, Jwt? jwt)`,
  `onSignIn(R user, Jwt? jwt)`, `beforeUpdate(T row, Jwt? jwt)`,
  `afterUpdateSuccess(T before, T after, Jwt? jwt)`. The docs drop it.
- `email.send.*` takes `table:`, not `collection:`
  (`MISSING_REQUIRED_ARGUMENT: 'table'` + `UNDEFINED_NAMED_PARAMETER: 'collection'`).

### 4. Rate limits — 1 snippet

`rate-limiting/overview.md:24`

`TableRateLimits` has no zero-arg constructor — it takes the schema:
`TaskRateLimits() : super(tasks)`. And every policy method returns
`Future<RateLimitPolicy?>`, not `RateLimitPolicy?`; the example is missing
`async`.

Note `customPolicy` now takes `String?` (see `6867b08` / #27) — worth checking
the rate-limiting pages agree while you're in there.

### 5. Assorted single-snippet signature drift

| Snippet | Error | Real API |
|---|---|---|
| `cron-jobs/overview.md:48` | `UNDEFINED_NAMED_PARAMETER: 'updates'` | check the current update-payload parameter name |
| `ai_templates.dart:563` / `:1580` | same `'updates'`, plus two `INVALID_CONSTANT` | same fix; the `const` needs dropping |
| `operations/overview.md:48` | `EXPECTED_CLASS_MEMBER` | a genuine syntax error in the example — read it |
| `external-idp.md:188` | `UNDEFINED_GETTER: 'table'` on `UserTable` | `TableMeta.getFor(schema)` / `tableName` |
| `rules/auth-rules.md:12` | `CLASS_USED_AS_MIXIN` on `AuthTableRules` | it's a class — `extends`, not `with`; and `UserTable` must satisfy `Table<User>` |
| `ai_templates.dart:196` / `:971` | `DUPLICATE_CONSTRUCTOR` | two unnamed constructors in one class |
| `ai_templates.dart:81` / `:862` | `RETURN_OF_INVALID_TYPE_FROM_CLOSURE` | nullable column accessors — same as group 2 |
| `ai_templates.dart:368` / `:1237` | `PostSummary` undefined | the view example is missing its own model class |
| `ai_templates.dart:425` / `:1314` / `:1327` | `EXTENDS_NON_CLASS`, `Jwt` undefined | missing import / wrong base class |

### 6. Needs a decision, not a fix — 2 snippets

**`rules/photo-rules.md:12`** extends `PhotoRules` and takes a `Photo`
parameter. Neither type exists anywhere in the codebase. The real types are
`PhotoEntry` / `PhotosTable`, and the only rules classes for them
(`PhotoTableRules`, `PhotoRowRules`) live under `libs/zonai_schema/lib/src/internal/`
and extend `InternalRowRules`, which isn't exported. So this page documents a
customization hook that either was removed or never shipped. **Ask before
rewriting it** — the fix might be to build the hook, or to delete the page.
(`docs/rules.md`'s photo example uses the correct `RowRules<PhotosTable, PhotoEntry>`
and passes, so there's a working model if the hook is meant to exist.)

**`docs/known-issues.md:594`** imports
`package:revali_router_annotations/revali_router_annotations.dart`, which the
playground doesn't depend on. This is a harness limitation rather than drift —
the snippet is about revali internals. Either add the dep to the playground's
dev_dependencies, or keep it baselined with that reason written on the line.

### 7. A fixture gap, not drift — 1 snippet

**`rules/row-rules.md:20`** uses `Task.createdBy` (`UNDEFINED_GETTER`). The
example is fine; the stand-in table is thin. Add a `createdBy` column to
`apps/playground/test/fixtures/doc_snippets/tasks.dart` (typed so `.value`
works — it's used as `before.createdBy.value`) rather than editing the doc.

The fixtures exist to carry whatever shape the examples reference. Extending one
is the right move whenever the example is correct and the fixture is what's
missing.

---

## Phase 2 — the ~200 unchecked fragments

Only 67 of 270 fences are checked. The rest are fragments: a bare `@override`
member, a few loose statements. Compiling them means knowing which class or
function body they belong in, which can't be inferred — so it needs an
authoring convention, and that's a maintainer call rather than something to
pick unilaterally. The usual shape is an info-string tag on the fence:

````
```dart in:TableRules<TaskTable, Task>
@override
Future<bool> canCreate(Jwt? jwt) async => jwt != null;
```
````

with `no-analyze` for the deliberately-partial ones. Tagging ~200 fences is the
bulk of the work; the extractor change is small. Worth agreeing the tag syntax
before anyone starts.

Two things the check will still never do, worth stating whenever it's cited as
coverage: it doesn't look at fragments, and it doesn't know whether an example
is *correct* — only that it compiles.
